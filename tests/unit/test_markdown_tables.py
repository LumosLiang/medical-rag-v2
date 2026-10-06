"""直接执行 SQL 文件中的 Python handler，测试的就是部署代码。"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULES = ROOT / 'src/ingestion/sql/chunk/structured_markdown'


def handler(name):
    namespace = {}
    exec((MODULES / f'{name}.sql').read_text().split('$$')[1], namespace)
    return namespace


def spans(text):
    return list(handler('extract_elements')['SplitTableSpans']().process(text))


def test_normalize_offsets_and_empty_page():
    result = handler('prepare_document')['normalize']([
        {'index': 2, 'content': ' B  \n\nC\r\n'},
        {'index': 0, 'content': '# A\n\ntext  '},
        {'index': 1, 'content': '\n '},
    ])
    assert result['text'] == '# A\ntext\n B\nC'
    assert result['pages'] == [
        {'page': 0, 'start': 0, 'end': 8},
        {'page': 2, 'start': 9, 'end': 13},
    ]


def test_adjacent_tables_stay_separate_and_offsets_are_exact():
    text = '# Results\nTable 1 First\n| A | B |\n| --- | --- |\n| x | 1 |\n| C | D |\n| --- | --- |\n| y | 2 |'
    result = spans(text)
    assert [s[1] for s in result] == ['TEXT', 'TABLE', 'TABLE']
    assert result[1][5]['caption'] == 'Table 1 First'
    for _, _, start, end, source, _ in result:
        assert text[start:end] == source
    assert len(result[1][5]['rows']) == 1
    assert len(result[2][5]['rows']) == 1


def test_caption_variants_multilevel_header_and_groups():
    for caption in ['Table 2. Results', 'Table 1 Results', '**Table 3. Results**']:
        text = caption + '\n| Name | Model |\n| --- | --- |\n| | OR (95% CI) |\n| Men | |\n| Low | 1.2 |\n| High | 2.4 |'
        table = spans(text)[0][5]
        assert table['caption'] == caption
        assert 'OR (95% CI)' in table['prefix']
        assert [r['group'] for r in table['rows']] == [0, 0, 0]


def test_packing_repeats_context_without_losing_data_rows():
    table = spans('Table 1. Test\n| X | Y |\n| --- | --- |\n| Group A | |\n| a | 1 |\n| b | 2 |')[0][5]
    table['prefix_tokens'] = 10
    for row in table['rows']:
        row['tokens'] = 10
    packed = list(handler('build_table_chunks')['PackTableRows']().process(table, 30))
    assert len(packed) == 2
    for _, text, start, end in packed:
        assert text.startswith(table['prefix'])
        assert '| Group A | |' in text
        assert start < end
    assert sum('| a | 1 |' in p[1] for p in packed) == 1
    assert sum('| b | 2 |' in p[1] for p in packed) == 1


def test_caption_can_precede_abbreviation_note():
    text = ('Table 1 Correlation\nCI, confidence interval; ICC, correlation.\n'
            '| X | Y |\n| --- | --- |\n| a | 1 |')
    table = spans(text)[0][5]
    assert table['prefix'].startswith('Table 1 Correlation\nCI,')


def test_header_only_table_keeps_exact_range():
    text = 'Table 1. Empty\n| X | Y |\n| --- | --- |'
    table = spans(text)[0][5]
    table['prefix_tokens'] = 12
    packed = list(handler('build_table_chunks')['PackTableRows']().process(table, 450))
    assert len(packed) == 1
    assert packed[0][3] == len(text)
    assert packed[0][1] == text


def locate(text, candidates, pages=None):
    document = {'text': text, 'pages': pages or [{'page': 0, 'start': 0, 'end': len(text)}]}
    return list(handler('annotate_chunks')['LocateChunks']().process(document, candidates))


def text_candidate(text, span_start=0, span_end=1000, span_index=0, headers=None):
    return {'kind': 'TEXT', 'text': text, 'span_start': span_start, 'span_end': span_end,
            'span_index': span_index, 'headers': headers or {}}


def test_locator_allows_overlap_across_pages():
    result = locate('abcdefghij', [text_candidate('abcdef'), text_candidate('defghij')],
                    [{'page': 0, 'start': 0, 'end': 5}, {'page': 1, 'start': 5, 'end': 10}])
    assert [row[3:6] for row in result] == [(0, 1, True), (0, 1, True)]


def test_sections_inherit_levels_across_table_and_clear_lower_level():
    text = '# Results\n## Outcomes\n### Old\nBefore\nTABLE\n### New\nAfter\n## Safety\nLast'
    table_start = text.index('TABLE')
    result = locate(text, [
        text_candidate('Before'),
        {'kind': 'TABLE', 'text': 'TABLE', 'start': table_start, 'end': table_start + 5},
        text_candidate('After', table_start + 5, len(text), 1),
        text_candidate('Last', table_start + 5, len(text), 1),
    ])
    assert [row[2] for row in result] == [
        'Results > Outcomes > Old', 'Results > Outcomes > Old',
        'Results > Outcomes > New', 'Results > Safety',
    ]


def test_locator_fallback_uses_span_pages_and_header_merge():
    text = '# Results\n## Outcomes\n### Old\nBefore\nTABLE\n### New\nAfter'
    start = text.index('### New')
    result = locate(text, [text_candidate('rewritten content', start, len(text), 1, {'h3': 'New'})],
                    [{'page': 0, 'start': 0, 'end': start}, {'page': 1, 'start': start, 'end': len(text)}])
    assert result[0][2:] == ('Results > Outcomes > New', 1, 1, False)


def test_markdown_table_caption_is_not_a_section_for_table_or_following_text():
    text = '# Results\n## Outcomes\n### Table 2. Mortality\n| A | B |\n| --- | --- |\n| x | 7 |\nFollowing text'
    start = text.index('| x |')
    result = locate(text, [
        {'kind': 'TABLE', 'text': '| x | 7 |', 'start': start, 'end': start + 9},
        text_candidate('Following text'),
    ])
    assert [row[2] for row in result] == ['Results > Outcomes', 'Results > Outcomes']


def test_fallback_does_not_replace_section_with_table_caption():
    text = '# Results\n## Outcomes\n### Table 2. Mortality\nData'
    start = text.index('Data')
    result = locate(text, [text_candidate(
        'rewritten', start, len(text), headers={'h3': 'Table 2. Mortality'}
    )])
    assert result[0][2] == 'Results > Outcomes'


def test_escaped_pipe_at_end_of_cell_is_preserved():
    parse_cells = handler('extract_elements')['cells']
    assert parse_cells(r'| Group | text\|') == ['Group', r'text\|']
    assert parse_cells(r'| Group | text\| |') == ['Group', r'text\|']


def test_repeated_table_group_label_keeps_its_source_page():
    table = spans('Table 1. Test\n| X | Y |\n| --- | --- |\n| Group A | |\n| a | 1 |\n| b | 2 |')[0][5]
    table['prefix_tokens'] = 10
    for row in table['rows']:
        row['tokens'] = 10
    packed = list(handler('build_table_chunks')['PackTableRows']().process(table, 30))
    # 第二块重复了更早页的 Group A，不能只引用 b 所在的页。
    assert packed[1][2] == table['rows'][0]['start']
    assert packed[1][3] == table['rows'][-1]['end']
