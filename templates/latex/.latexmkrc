# latexmk : PDF via pdflatex, mode non interactif, SyncTeX pour aller du PDF au source
$pdf_mode = 1;
$pdflatex = 'pdflatex -interaction=nonstopmode -synctex=1 -file-line-error %O %S';
$clean_ext = 'synctex.gz run.xml bbl nav snm vrb';
