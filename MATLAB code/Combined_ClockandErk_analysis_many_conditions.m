clear; clc; close all;

% --- Step 1: Prompt user for Excel file ---
[filename, pathname] = uigetfile('*.xlsx', 'Select the Excel file with multiple sheets');
if isequal(filename, 0)
    error('No file selected.');
end
filePath = fullfile(pathname, filename);

% --- Step 2: Read all sheet names ---
[~, sheetNames] = xlsfinfo(filePath);

% --- Step 3: Set smoothing parameters ---
sgolay_order_clock = 0;     
frame_length_clock = 5;    
sgolay_order_erk = 0;       
frame_length_erk = 5;       

% Ensure odd frame lengths
if mod(frame_length_clock, 2) == 0
    frame_length_clock = frame_length_clock + 1;
end
if mod(frame_length_erk, 2) == 0
    frame_length_erk = frame_length_erk + 1;
end

% --- Step 4: Initialize storage ---
colors = lines(length(sheetNames));
sheetLabels = {};
clockMatrix = [];
clockSEMMatrix = [];
erkMatrix = [];
erkSEMMatrix = [];
allTime = {};

% --- Step 5: Process each sheet ---
for s = 1:length(sheetNames)
    sheet = sheetNames{s};
    data = readmatrix(filePath, 'Sheet', sheet);

    if isempty(data)
        continue;
    end

    time = data(:,1); 
    rest = data(:,2:end); 
    nCols = size(rest,2);
    halfCols = nCols/2;

    if mod(nCols, 2) ~= 0
        error(['In sheet ' sheet ', number of data columns after time is not even.']);
    end

    clockData_raw = rest(:, 1:halfCols);
    erkData_raw = rest(:, halfCols+1:end);

    % Smooth Clock and ERK separately
    clockData_smooth = NaN(size(clockData_raw));
    erkData_smooth = NaN(size(erkData_raw));

    for col = 1:halfCols
        if all(isnan(clockData_raw(:,col)))
            continue;
        end
        clockData_smooth(:, col) = sgolayfilt(clockData_raw(:, col), sgolay_order_clock, frame_length_clock);

        if all(isnan(erkData_raw(:,col)))
            continue;
        end
        erkData_smooth(:, col) = sgolayfilt(erkData_raw(:, col), sgolay_order_erk, frame_length_erk);
    end

    % --- Correctly calculate MEDIAN and SEM across samples ---
    medianClock = median(clockData_smooth, 2, 'omitnan');
    semClock    = std(clockData_smooth, 0, 2, 'omitnan') ./ sqrt(sum(~isnan(clockData_smooth),2));
   

    medianERK   = median(erkData_smooth, 2, 'omitnan');
    semERK      = std(erkData_smooth, 0, 2, 'omitnan') ./ sqrt(sum(~isnan(erkData_smooth),2));

    % --- Store ---
    allTime{s} = time;
    sheetLabels{s} = sheet;

    maxLength = max(size(clockMatrix,1), length(medianClock));
    if size(clockMatrix,1) < maxLength
        clockMatrix(end+1:maxLength, :) = NaN;
        clockSEMMatrix(end+1:maxLength, :) = NaN;
        erkMatrix(end+1:maxLength, :) = NaN;
        erkSEMMatrix(end+1:maxLength, :) = NaN;
    end
    if length(medianClock) < maxLength
        medianClock(end+1:maxLength,1) = NaN;
        semClock(end+1:maxLength,1) = NaN;
        medianERK(end+1:maxLength,1) = NaN;
        semERK(end+1:maxLength,1) = NaN;
    end

    clockMatrix(:,s) = medianClock;
    clockSEMMatrix(:,s) = semClock;
    erkMatrix(:,s) = medianERK;
    erkSEMMatrix(:,s) = semERK;
end
sgolay_order_clock = 0;     
frame_length_clock = 5;    
sgolay_order_erk = 0;       
frame_length_erk = 5;  
clockMatrix = sgolayfilt(clockMatrix, sgolay_order_erk, 7);
erkMatrix = sgolayfilt(erkMatrix, sgolay_order_erk, 7);

% --- Step 6: Normalize Clock Periods Grouped (Condition 1-2 by 1, 3-4 by 3 etc.) ---
GroupedNormClockMatrix = NaN(size(clockMatrix));
for s = 1:2:size(clockMatrix,2)
    minVal = min(clockMatrix(:,s), [], 'omitnan');
    GroupedNormClockMatrix(:,s) = clockMatrix(:,s) / minVal;
    if s+1 <= size(clockMatrix,2)
        GroupedNormClockMatrix(:,s+1) = clockMatrix(:,s+1) / minVal;
    end
end

GroupedNormClockSEMMatrix = NaN(size(clockSEMMatrix));
for s = 1:2:size(clockMatrix,2)
    minVal = min(clockMatrix(:,s), [], 'omitnan');
    GroupedNormClockSEMMatrix(:,s) = clockSEMMatrix(:,s) / minVal;
    if s+1 <= size(clockMatrix,2)
        GroupedNormClockSEMMatrix(:,s+1) = clockSEMMatrix(:,s+1) / minVal;
    end
end

% --- Step 7: Plot Clock Periods (Median ± SEM) ---
hold on;  % Ensure all plots go on the same axes

for s = 1:length(sheetLabels)
    timeVec = allTime{s};
    medianClk = clockMatrix(:,s);
    semClk = clockSEMMatrix(:,s);

    % --- Make sizes match ---
    if length(timeVec) < length(medianClk)
        timeVec(end+1:length(medianClk)) = NaN;
    elseif length(timeVec) > length(medianClk)
        timeVec = timeVec(1:length(medianClk));
    end

    valid = ~isnan(timeVec) & ~isnan(medianClk) & ~isnan(semClk);

    % --- Plot SEM shaded region (excluded from legend) ---
    fill([timeVec(valid); flipud(timeVec(valid))], ...
         [medianClk(valid) - semClk(valid); flipud(medianClk(valid) + semClk(valid))], ...
         colors(s,:), 'FaceAlpha', 0.3, 'EdgeColor', 'none', ...
         'HandleVisibility', 'off');

    % --- Plot median curve (included in legend) ---
    plot(timeVec(valid), medianClk(valid), '-', ...
         'Color', colors(s,:), 'LineWidth', 2, ...
         'DisplayName', sheetLabels{s});
end

xlabel('Time (minutes)');
ylabel('Clock Period (minutes)');
title('Clock Periods (Median ± SEM)');
legend('Location', 'bestoutside');
grid on;
hold off;

% --- Step 8: Plot ERK Levels (Median ± SEM) ---
figure;
hold on;
for s = 1:length(sheetLabels)
    timeVec = allTime{s};
    medianERK = erkMatrix(:,s);
    semERK = erkSEMMatrix(:,s);

    if length(timeVec) < length(medianERK)
        timeVec(end+1:length(medianERK)) = NaN;
    elseif length(timeVec) > length(medianERK)
        timeVec = timeVec(1:length(medianERK));
    end

    valid = ~isnan(timeVec) & ~isnan(medianERK) & ~isnan(semERK);

    fill([timeVec(valid); flipud(timeVec(valid))], ...
         [medianERK(valid) - semERK(valid); flipud(medianERK(valid) + semERK(valid))], ...
         colors(s,:), 'FaceAlpha', 0.3, 'EdgeColor', 'none', ...
         'HandleVisibility', 'off');  % Exclude SEM from legend

    plot(timeVec(valid), medianERK(valid), '-', 'Color', colors(s,:), ...
         'LineWidth', 2, 'DisplayName', sheetLabels{s});
end
xlabel('Time (minutes)');
ylabel('ERK activity (a.u)');
title('ERK Activity (Median ± SEM)');
legend('Location', 'bestoutside');
grid on;
hold off;

% --- Step 9: Plot Grouped Normalized Clock Periods ---
figure;
hold on;
for s = 1:length(sheetLabels)
    timeVec = allTime{s};
    gclock = GroupedNormClockMatrix(:,s);
    gsem = GroupedNormClockSEMMatrix(:,s);

    if length(timeVec) < length(gclock)
        timeVec(end+1:length(gclock)) = NaN;
    elseif length(timeVec) > length(gclock)
        timeVec = timeVec(1:length(gclock));
    end

    valid = ~isnan(timeVec) & ~isnan(gclock) & ~isnan(gsem);

    fill([timeVec(valid); flipud(timeVec(valid))], ...
         [gclock(valid) - gsem(valid); flipud(gclock(valid) + gsem(valid))], ...
         colors(s,:), 'FaceAlpha', 0.3, 'EdgeColor', 'none', ...
         'HandleVisibility', 'off');  % Exclude SEM from legend

    plot(timeVec(valid), gclock(valid), '-', 'Color', colors(s,:), ...
         'LineWidth', 2, 'DisplayName', sheetLabels{s});
end
xlabel('Time (minutes)');
ylabel('Normalized Clock Period (a.u)');
title('Normalized Clock Periods (Median ± SEM)');
legend('Location', 'bestoutside');
grid on;
hold off;

GroupedNorm_first_tp_ClockMatrix = NaN(size(clockMatrix));
% --- Step 10: Plot Clock Periods Normalized to First Timepoint (Median ± SEM) ---
figure;
hold on;
for s = 1:length(sheetLabels)
    timeVec = allTime{s};
    medianClk = clockMatrix(:,s);
    semClk = clockSEMMatrix(:,s);

    % Normalize to first valid timepoint
    firstVal = medianClk(find(~isnan(medianClk),1,'first'));
    normClk = medianClk / firstVal;
    normSem = semClk / firstVal;
    normSemClk(:,s)=normSem;
    GroupedNorm_first_tp_ClockMatrix(:,s) = normClk;

    if length(timeVec) < length(normClk)
        timeVec(end+1:length(normClk)) = NaN;
    elseif length(timeVec) > length(normClk)
        timeVec = timeVec(1:length(normClk));
    end

    valid = ~isnan(timeVec) & ~isnan(normClk) & ~isnan(normSem);

    % SEM shading
    fill([timeVec(valid); flipud(timeVec(valid))], ...
         [normClk(valid) - normSem(valid); flipud(normClk(valid) + normSem(valid))], ...
         colors(s,:), 'FaceAlpha', 0.3, 'EdgeColor', 'none', ...
         'HandleVisibility', 'off');

    % Median line
    plot(timeVec(valid), normClk(valid), '-', ...
         'Color', colors(s,:), 'LineWidth', 2, ...
         'DisplayName', sheetLabels{s});
end
xlabel('Time (minutes)');
ylabel('Clock Period (normalized to first timepoint)');
title('Clock Periods Normalized to First Timepoint (Median ± SEM)');
legend('Location', 'bestoutside');
grid on;
hold off;


% --- Step 11: Plot ERK Levels Normalized to First Timepoint (Median ± SEM) ---
GroupedNorm_first_tp_ERK_Matrix = NaN(size(clockMatrix));
figure;
hold on;
for s = 1:length(sheetLabels)
    timeVec = allTime{s};
    medianERK = erkMatrix(:,s);
    semERK = erkSEMMatrix(:,s);

    % Normalize to first valid timepoint
    firstVal = medianERK(find(~isnan(medianERK),1,'first'));
    normERK = medianERK / firstVal;
    normSem = semERK / firstVal;
    normSemERK(:,s)=normSem;
    GroupedNorm_first_tp_ERK_Matrix(:,s)= normERK;

    if length(timeVec) < length(normERK)
        timeVec(end+1:length(normERK)) = NaN;
    elseif length(timeVec) > length(normERK)
        timeVec = timeVec(1:length(normERK));
    end

    valid = ~isnan(timeVec) & ~isnan(normERK) & ~isnan(normSem);

    % SEM shading
    fill([timeVec(valid); flipud(timeVec(valid))], ...
         [normERK(valid) - normSem(valid); flipud(normERK(valid) + normSem(valid))], ...
         colors(s,:), 'FaceAlpha', 0.3, 'EdgeColor', 'none', ...
         'HandleVisibility', 'off');

    % Median line
    plot(timeVec(valid), normERK(valid), '-', ...
         'Color', colors(s,:), 'LineWidth', 2, ...
         'DisplayName', sheetLabels{s});
end
xlabel('Time (minutes)');
ylabel('ERK Activity (normalized to first timepoint)');
title('ERK Activity Normalized to First Timepoint (Median ± SEM)');
legend('Location', 'bestoutside');
grid on;
hold off;
