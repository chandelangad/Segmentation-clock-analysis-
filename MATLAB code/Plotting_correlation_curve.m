clear; clc; close all;

% Step 1: Prompt user for Excel file
[filename, pathname] = uigetfile('*.xlsx', 'Select the Excel file with multiple sheets');
if isequal(filename, 0)
    error('No file selected.');
end
filePath = fullfile(pathname, filename);

% Step 2: Get all sheet names
[~, sheetNames] = xlsfinfo(filePath);

% Step 3: Loop through sheets in pairs
conditions = {};
results = struct();

for i = 1:2:length(sheetNames)
    % Extract condition name (before '_')
    condName = erase(sheetNames{i}, '_Clock period');
    conditions{end+1} = condName;
    
    % --- Read Clock period sheet ---
    clockData = readmatrix(filePath, 'Sheet', sheetNames{i});
    clockVals = clockData(:,2:end); % remove time column
    
    % --- Read ERK sheet ---
    erkData = readmatrix(filePath, 'Sheet', sheetNames{i+1});
    erkVals = erkData(:,2:end); % remove time column
    
    % --- Match dimensions ---
    minRows = min(size(clockVals,1), size(erkVals,1));
    minCols = min(size(clockVals,2), size(erkVals,2));
    clockVals = clockVals(1:minRows, 1:minCols);
    erkVals   = erkVals(1:minRows, 1:minCols);
    
    % --- Flatten into vectors ---
    clockVec = clockVals(:);
    erkVec   = erkVals(:);
    
    % --- Remove NaNs ---
    validIdx = ~isnan(clockVec) & ~isnan(erkVec);
    clockVec = clockVec(validIdx);
    erkVec   = erkVec(validIdx);
    
    % --- Compute correlation coefficient ---
    R = corrcoef(clockVec, erkVec);
    rVal = R(1,2);
    R2 = rVal; % coefficient of determination
    results.(condName).R2 = R2;
    
    % --- Plot correlation curve ---
    figure;
    scatter(clockVec, erkVec, 40, 'filled'); hold on;
    
    % Add regression line
    p = polyfit(clockVec, erkVec, 1);
    yfit = polyval(p, clockVec);
    plot(clockVec, yfit, 'r-', 'LineWidth', 2);
    
    xlabel('Clock Period');
    ylabel('ERK Activity');
    title([condName ' : Clock Period vs ERK Activity']);
    grid on;
    
    % Display R2 value on plot
    xpos = min(clockVec) + 0.05*(max(clockVec)-min(clockVec));
    ypos = max(erkVec) - 0.1*(max(erkVec)-min(erkVec));
    text(xpos, ypos, sprintf('R^2 = %.3f', R2), ...
        'FontSize', 12, 'FontWeight', 'bold', 'BackgroundColor','w');
end

% Step 4: Print R2 results
disp('Coefficient of determination (R^2):');
for k = 1:length(conditions)
    fprintf('%s: R^2 = %.3f\n', conditions{k}, results.(conditions{k}).R2);
end
