clear; clc;

% --- Prompt user to select data file ---
[filename, pathname] = uigetfile({'*.csv;*.xlsx','CSV or Excel Files'}, 'Select your data file');
if isequal(filename, 0)
    error('No file selected.');
end

% --- Load data ---
filePath = fullfile(pathname, filename);
[~, ~, ext] = fileparts(filePath);

if strcmpi(ext, '.csv')
    data = readmatrix(filePath);
elseif strcmpi(ext, '.xlsx')
    data = readmatrix(filePath);
else
    error('Unsupported file type.');
end

[numRows, numCols] = size(data);
shifts = zeros(1, numCols); % Store peak indices
maxShift = 0;

% --- Step 1: Find first peak index per column ---
for col = 1:numCols
    signal = data(:, col);
    if all(isnan(signal))
        continue;
    end

    % Smooth to suppress noise (optional)
    smooth_signal = movmean(signal, 3, 'omitnan');

    % Find first prominent peak
    [~, locs] = findpeaks(smooth_signal, 'MinPeakProminence', 0.1);

    if ~isempty(locs)
        shifts(col) = locs(1);  % First peak index
        maxShift = max(maxShift, locs(1));
    else
        shifts(col) = NaN;
    end
end

% --- Step 2: Align each column to the first peak by padding with NaNs ---
alignedData = NaN(numRows + maxShift, numCols);

for col = 1:numCols
    if isnan(shifts(col)) || shifts(col) == 0
        continue;
    end

    shiftAmount = maxShift - shifts(col);
    alignedData((1 + shiftAmount):(shiftAmount + numRows), col) = data(:, col);
end

% --- Plotting: Before and After Alignment ---
figure;

subplot(1,2,1);
plot(data, 'LineWidth', 1);
title('Original Signals');
xlabel('Time'); ylabel('Signal'); grid on;

subplot(1,2,2);
plot(alignedData, 'LineWidth', 1);
title('Aligned Signals (to First Peak)');
xlabel('Aligned Time'); ylabel('Signal'); grid on;
