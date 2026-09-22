% Prompt user to select the Excel file
[file, path] = uigetfile({'*.xlsx;*.xls'}, 'Select Excel file containing wrapped phase values');
if isequal(file, 0)
    disp('No file selected. Exiting...');
    return;
end

% Read the data
phaseData = readmatrix(fullfile(path, file));  % Each column is a sample, each row is a timepoint

% Initialize output matrix
totalPhase = zeros(size(phaseData));

% Unwrap phase for each sample (column)
for col = 1:size(phaseData, 2)
    wrappedPhase = phaseData(:, col);
    unwrapped = unwrap(wrappedPhase);  % MATLAB's unwrap assumes jumps of 2*pi
    totalPhase(:, col) = unwrapped;
end

% Optional: Save to Excel
writematrix(totalPhase, fullfile(path, 'totalPhase_output.xlsx'));
disp('Unwrapped total phase saved as totalPhase_output.xlsx');
