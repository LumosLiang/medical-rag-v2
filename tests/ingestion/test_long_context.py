"""检查长窗口策略的边界、证据保留与页码；直接执行 SQL 中的 handler。"""
from pathlib import Path

MODULES = Path(__file__).resolve().parents[2] / 'src/ingestion/sql/chunk/strategies/structured_markdown'
HANDLERS = {
    'prepare_document': 'document/prepare_document.sql',
    'split_abstract_spans': 'document/split_abstract_spans.sql',
    'table_notes': 'tables/attach_notes.sql',
}


def handler(name):
    namespace = {}
    exec((MODULES / HANDLERS[name]).read_text().split('$$')[1], namespace)
    return namespace


def document(text, boundary=None):
    pages = [{'page': 0, 'start': 0, 'end': len(text)}]
    if boundary is not None:
        pages = [{'page': 0, 'start': 0, 'end': boundary},
                 {'page': 1, 'start': boundary + 1, 'end': len(text)}]
    return {'text': text, 'pages': pages}


def test_empty_options_preserve_old_strategy():
    value = document('# Abstract\ntext\n# References\nref')
    assert handler('prepare_document')['clean'](value, {}) == value


def test_reference_filter_preserves_appendix_and_in_text_citations():
    text = '# Results\nSupported [12].\n# References\n12. Paper\n# Appendix\nOther evidence'
    result = handler('prepare_document')['clean'](document(text), {'drop_reference_sections': True})
    assert result['text'] == '# Results\nSupported [12].\n# Appendix\nOther evidence'


def test_cross_page_cleanup_recalculates_ranges():
    text = '# Abstract\nFirst\nCopyright 2024\nSecond\n# Introduction\nBody'
    boundary = text.index('\nSecond')
    result = handler('prepare_document')['clean'](document(text, boundary),
        {'preserve_abstract': True, 'drop_publication_noise': True})
    assert 'Copyright' not in result['text']
    assert result['text'][result['pages'][1]['start']:result['pages'][1]['end']].startswith('Second')
    abstract = result['abstracts'][0]
    assert result['text'][abstract['start']:abstract['end']].strip() == '# Abstract\nFirst\nSecond'


def test_structured_abstract_keeps_nested_labels_until_introduction():
    text = '# Abstract\n## Background\nA\n## Methods\nB\n## Results\nC\n## Conclusions\nDone\n# 1. Introduction\nD'
    result = handler('prepare_document')['clean'](document(text), {'preserve_abstract': True})
    assert result['abstracts'][0]['end'] == result['text'].index('# 1. Introduction')


def test_unheaded_abstract_requires_methods_results_conclusion():
    text = '# Paper\nBackground: A\nMethods: B\nResults: C\nConclusions: D\n# Introduction\nE'
    result = handler('prepare_document')['clean'](document(text), {'preserve_abstract': True})
    abstract = result['abstracts'][0]
    assert result['text'][abstract['start']:abstract['end']].endswith('Conclusions: D')
    result = handler('prepare_document')['clean'](document('Background: a normal paragraph'), {'preserve_abstract': True})
    assert result['abstracts'] == []


def test_abstract_intersection_does_not_duplicate_table_or_text():
    text = 'before\nabstract\nafter'
    result = list(handler('split_abstract_spans')['SplitAbstractSpans']().process(
        text, 10, [{'start': 17, 'end': 25}]))
    assert [row[1] for row in result] == ['TEXT', 'ABSTRACT', 'TEXT']
    assert ''.join(row[4] for row in result) == text
    for _, _, start, end, value in result:
        assert text[start - 10:end - 10] == value


def test_table_notes_stop_before_body_and_include_source_range():
    text = 'TABLE\nNote: CI is confidence interval.\nFollowing paragraph'
    table = {'prefix': 'header'}
    result = handler('table_notes')['attach'](table, text, 5, True)
    assert result['prefix'] == 'header\nNote: CI is confidence interval.'
    assert result['notes_end'] == text.index('Following')
    assert handler('table_notes')['attach'](table, text, 5, False) == {'prefix': 'header'}


def test_body_lower_level_header_ends_abstract_without_introduction():
    text = '# Abstract\nSummary text\n## Methods\n### Study population\nBody'
    result = handler('prepare_document')['clean'](document(text), {'preserve_abstract': True})
    assert result['abstracts'][0]['end'] == text.index('## Methods')


def test_body_summary_and_repeated_abstract_are_not_new_abstracts():
    text = '# Abstract\nActual abstract\n# Introduction\nBody\n## Abstract\nPage header\n## Summary\nDiscussion summary'
    result = handler('prepare_document')['clean'](document(text), {'preserve_abstract': True})
    assert result['abstracts'] == [{'start': 0, 'end': text.index('# Introduction')}]


def test_keywords_end_abstract_before_abbreviation_table():
    text = '# ABSTRACT\nMethods: Study\nResults: Finding\nConclusion: Done\nKeywords: disease\nAbbreviations\n| A | B |\nINTRODUCTION\nBody'
    result = handler('prepare_document')['clean'](document(text), {'preserve_abstract': True})
    assert result['abstracts'][0]['end'] == text.index('Keywords:')
