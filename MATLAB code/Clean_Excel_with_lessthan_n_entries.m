% --- Step 1: Prompt user to select Excel file ---
[filename, pathname] = uigetfile('*.xlsx', 'Select the Excel file with multiple sheets');
if isequal(filename, 0)
    error('No file selected.');
end
filePath = fullfile(pathname, filename);

% --- Step 2: Read all sheet names ---
[~, sheetNames] = xlsfinfo(filePath);

% --- Step 3: Create a new file to save cleaned data ---
[~, nameOnly, ~] = fileparts(filename);
cleanedFile = fullfile(pathname, [nameOnly '_cleaned.xlsx']);

% --- Step 4: Process each sheet ---
for i = 1:length(sheetNames)
    sheetName = sheetNames{i};
    data = readtable(filePath, 'Sheet', sheetName);

    % Count non-missing entries per column
    nonMissingCounts = sum(~ismissing(data));

    % Keep only columns with >= 15 non-missing entries
    dataCleaned = data(:, nonMissingCounts >= 15);

    % Write cleaned sheet to new file
    writetable(dataCleaned, cleanedFile, 'Sheet', sheetName);
end

disp('Columns with fewer than 15 entries removed from all sheets.');
