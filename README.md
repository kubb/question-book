# question-book
Word-to-LaTeX and Word-to-Docbook transformation scripts. Designed specifically to help transcribing a question-answer textbook.

How to prepare source documents
- Use required template, containing necessary styles for defining of QALOs
- Organize documents into folders, each folder represents a chapter
- Only one level of chapters is allowed
- Each word file represents a subchapter
- Each word file must be contained within a folder (chapter)
- Word file may contain multiple QALOs
- Every folder (chapter) name must start with two characters designating its number (e.g. "01 Analysis", "02 Desing")
- Every word file (subchapter) name must start with five characters designating the number of chapter and number of subchapter, FOLLOWED BY SPACE (e.g. "01.01 Analysis of information systems", "02.10 Distributed system design")
- If the name of a chapter starts with "[ignore]" prefix, it will be omitted (e.g. "[ignore] helping matter")
- Every chapter should contain a word file designated as "XX.00 [Main]", where XX stands for chapter number. This file should contain those QALOs, that are to be directly placed into chapter, and not witnin a subchapter.


ENCODING
- hardcodnute stringy su windows 1250
- vnutro zdrojovych suborov je UTF-8
