% Report whether a file starts with a PDF header.
% Set the file name below before running.

header = '%PDF-1.7';
filename = 'document.pdf';

fid = fopen(filename, 'r');
bytes = fread(fid, numel(header), '*char')';
fclose(fid);

if strcmp(bytes, header)
    disp('PDF header found');
else
    disp('No PDF header');
end
