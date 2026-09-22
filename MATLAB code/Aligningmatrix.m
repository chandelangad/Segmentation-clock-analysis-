clear all;
% Prompt user to select a CSV file
[filename, pathname] = uigetfile('*.csv', 'Select the CSV file');
if isequal(filename, 0)
    error('No file selected.');
end

% Read the CSV file into a matrix
filePath = fullfile(pathname, filename);
combinedData = readmatrix(filePath);

[m, n] = size(combinedData);

% Ensure the number of columns is even
if mod(n, 2) ~= 0
    error('The number of columns in the matrix must be even.');
end

% Preallocate output matrix with NaNs
alignedData = NaN(m, n);

% Copy the first half directly
alignedData(:, 1:n/2) = combinedData(:, 1:n/2);

% Align second half with first half
for i = 1:n/2
    col1 = combinedData(:, i);
    col2 = combinedData(:, i + n/2);

    % Find the first non-NaN and non-zero index in each column
    idx1 = find(~isnan(col1) & col1 ~= 0, 1);
    idx2 = find(~isnan(col2) & col2 ~= 0, 1);

    if isempty(idx1) || isempty(idx2)
        continue; % Skip if column has no valid data
    end

    % Calculate the shift amount
    shift = idx1 - idx2;

    % Shift the second-half column to align with the first-half
    if shift >= 0
        alignedData((1+shift):m, i + n/2) = col2(1:(m-shift));
    else
        alignedData(1:(m+shift), i + n/2) = col2((1-shift):m);
    end
end
%% 

% Extract ERK-aligned columns (n/2+1 to end)
ERK_aligned_raw = alignedData(:, n/2+1:end);

smooth_order = 0;
frame_length = 8;
if mod(frame_length, 2) == 0
    frame_length = frame_length + 1;
end

[m_rows, n_cols] = size(ERK_aligned_raw);
ERK_aligned = NaN(m_rows, n_cols);  % Preallocate smoothed matrix

% Smooth each column only where enough data exists
for col = 1:n_cols
    y = ERK_aligned_raw(:, col);
    if sum(~isnan(y)) >= frame_length
        % Only smooth the valid portion (no extrapolation)
        validIdx = find(~isnan(y));
        y_smooth = sgolayfilt(y(validIdx), smooth_order, frame_length);
        ERK_aligned(validIdx, col) = y_smooth;
    end
end

% --- Slope calculation parameters ---
sgolay_order = 1;      % First derivative
frame_length = 9;      % Must be odd
dt = 1;                % Time step
if mod(frame_length, 2) == 0
    frame_length = frame_length + 1;
end
halfWin = (frame_length - 1) / 2;

% Get derivative filter coefficients
[~, G] = sgolay(sgolay_order, frame_length);

% Initialize slope and normalized slope matrices
slopeData = NaN(size(ERK_aligned));
normSlopeData = NaN(size(ERK_aligned));

% Loop through each column
for col = 1:size(ERK_aligned, 2)
    y = ERK_aligned(:, col);

    % Skip if not enough valid points
    if sum(~isnan(y)) < frame_length
        continue;
    end

    % Compute slope where possible (no interpolation)
    dy = NaN(size(y));
    for t = (halfWin+1):(length(y)-halfWin)
        window = y((t - halfWin):(t + halfWin));
        if any(isnan(window))
            continue;  % Skip if window has NaN
        end
        dy(t) = dot(G(:,2), window);
    end

    slopeData(:, col) = dy / dt;

    % Normalize slope by column mean (excluding NaNs)
    colMean = mean(y, 'omitnan');
    if colMean ~= 0
        % Normalize slope pointwise by smoothed ERK value at the same time point
        normSlopeData(:, col) = slopeData(:, col) ./ ERK_aligned(:, col);

    end
end
%% 
% --- Compute mean and SEM ---
computeMeanSEM = @(X) deal( ...
    mean(X, 2, 'omitnan'), ...
    std(X, 0, 2, 'omitnan') ./ sqrt(sum(~isnan(X), 2)) ...
);

[mean_ERK, sem_ERK] = computeMeanSEM(ERK_aligned);
[mean_slope, sem_slope] = computeMeanSEM(slopeData);
[mean_normSlope, sem_normSlope] = computeMeanSEM(normSlopeData);

time = (1:length(mean_ERK))';

% --- Plot all with error bars in subplots ---
figure;

% 1. ERK
subplot(3,1,1);
errorbar(time, mean_ERK, sem_ERK, 'b', 'LineWidth', 1.5); hold on;
ylabel('ERK (a.u.)');
title('Smoothed ERK Signal ± SEM');
grid on;

% 2. Slope
subplot(3,1,2);
errorbar(time, mean_slope, sem_slope, 'r', 'LineWidth', 1.5); hold on;
ylabel('Slope (a.u./time)');
title('ERK Slope ± SEM');
grid on;

% 3. Normalized Slope
subplot(3,1,3);
errorbar(time, mean_normSlope, sem_normSlope, 'g', 'LineWidth', 1.5); hold on;
xlabel('Time');
ylabel('Slope / Mean ERK');
title('Normalized ERK Slope ± SEM');
grid on;
