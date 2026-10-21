{ pkgs }: {
  # What the document skills shell out to: Claude's docx/pdf/pptx/xlsx (from
  # the claude.ai skill sync) and Codex's doc/pdf/spreadsheet/slides (from
  # home/skills.nix). These go on the agent wrappers' PATH, not the user
  # profile. The skills npm-install their JS libraries (pptxgenjs, docx, ...)
  # per workspace.
  tools = with pkgs; [
    (python3.withPackages (ps: with ps; [
      defusedxml
      lxml
      markitdown
      matplotlib
      openpyxl
      pandas
      pdf2image
      pdfplumber
      pillow
      pypdf
      pytesseract
      python-docx
      python-pptx
      reportlab
    ] ++ (with markitdown.optional-dependencies; docx ++ outlook ++ pdf ++ pptx ++ xls ++ xlsx)))
    ghostscript
    imagemagick
    inkscape
    libreoffice
    pandoc
    poppler-utils
    qpdf
    tesseract
  ];

  # Without these the only font is DejaVu Sans, and LibreOffice renders every
  # document in it. They are metric-compatible with the Office defaults
  # (Arial, Times New Roman, Courier New, Calibri, Cambria), so rendered pages
  # lay out like the originals.
  fonts = with pkgs; [
    caladea
    carlito
    dejavu_fonts
    liberation_ttf
  ];
}
