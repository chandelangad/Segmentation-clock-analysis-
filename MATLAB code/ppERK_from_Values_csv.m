clear all;

% ============================================================
%  ppERK-only pipeline
%  Reads the FIJI plot-profile files  Values_ppERK_*.csv  directly
%  (one file per z-slice / measurement), averages them per subfolder,
%  then smooths / baseline-corrects / finds peaks / plots.
% ============================================================

% ---- User settings ----------------------------------------
targetSubfolderName = '';        % CSVs sit directly in each subfolder (e.g. 'dpERK_No Hs_3')
normalizeByMask     = false;     % raw ppERK, no mask division% set to '' if the CSVs sit directly in each subfolder
filePrefix          = 'Values_ppERK_';        % change to 'Value_ppERK_' if that's how yours are named
% -----------------------------------------------------------

% Prompt user to select the parent folder
parentDir = uigetdir('', 'Select the parent folder');
if parentDir == 0
    disp('No folder selected. Exiting...');
    return;
end
[parentPath, parentFolderName, ~] = fileparts(parentDir);

% Get valid subfolders
subfolders = dir(parentDir);
subfolders = subfolders([subfolders.isdir] & ~startsWith({subfolders.name}, '.'));

% Aggregated results (one column per successfully-processed subfolder)
Avg_ppERK   = [];
validNames  = {};   % subfolder names, aligned with columns of Avg_ppERK
col_idx     = 0;    % counts columns actually written
maxRows     = 0;

% Loop through each subfolder
for i = 1:length(subfolders)
    subfolderPath = fullfile(parentDir, subfolders(i).name);

    if isempty(targetSubfolderName)
        targetSubfolder = subfolderPath;
    else
        targetSubfolder = fullfile(subfolderPath, targetSubfolderName);
    end

    if ~isfolder(targetSubfolder)
        disp(['Skipping folder: ', subfolders(i).name, ' (target subfolder not found)']);
        continue;
    end

    % ---- Grab ONLY the ppERK plot-profile files ----
    files = dir(fullfile(targetSubfolder, [filePrefix, '*.csv']));
    if isempty(files)
        disp(['No ', filePrefix, '*.csv files in: ', targetSubfolder]);
        continue;
    end

    % Read each file (column 2 = "Value") into a column of abody_val_ppERK
    abody_val_ppERK = [];
    for j = 1:length(files)
        fileName = fullfile(targetSubfolder, files(j).name);
        T        = readtable(fileName);
        colData  = T{:, 2};

        % Pad within-subfolder columns to equal length (usually already equal)
        rowsNow = size(abody_val_ppERK, 1);
        if isempty(abody_val_ppERK)
            abody_val_ppERK = colData;
        else
            n = max(rowsNow, numel(colData));
            if size(abody_val_ppERK, 1) < n
                abody_val_ppERK(end+1:n, :) = NaN;
            end
            if numel(colData) < n
                colData(end+1:n, 1) = NaN;
            end
            abody_val_ppERK = [abody_val_ppERK, colData]; %#ok<AGROW>
        end
    end

    % Mean profile across all slices/files for this subfolder
    meanProfile = mean(abody_val_ppERK, 2, 'omitnan');

    % Store as the next column of Avg_ppERK (NaN-pad rows as needed)
    col_idx = col_idx + 1;
    maxRows = max(maxRows, numel(meanProfile));
    if size(Avg_ppERK, 1) < maxRows
        Avg_ppERK(end+1:maxRows, :) = NaN;
    end
    if numel(meanProfile) < maxRows
        meanProfile(end+1:maxRows, 1) = NaN;
    end
    Avg_ppERK(:, col_idx) = meanProfile;
    validNames{col_idx}   = subfolders(i).name; %#ok<SAGROW>
end

if col_idx == 0
    error('No subfolders yielded %s*.csv files.', filePrefix);
end

% ---- Clean legend names (prefix + trailing number) ----
cleanedNames = cell(1, numel(validNames));
for i = 1:numel(validNames)
    parts  = split(validNames{i}, '_');
    prefix = parts{1};
    trailingNum = regexp(validNames{i}, '_\d+', 'match');
    if ~isempty(trailingNum)
        cleanedNames{i} = sprintf('%s-%s', prefix, strrep(trailingNum{end}, '_', ''));
    else
        cleanedNames{i} = validNames{i};   % fallback if no trailing number
    end
end

%% Smoothing
windowSize = 51; polyOrder = 3;
smoothed_ppERK = sgolayfilt(Avg_ppERK, polyOrder, windowSize, [], 1);

% Extra smoothening just to get the baseline value
% windowSize = 101; polyOrder = 1;
smoothed_ppERK_1 = sgolayfilt(Avg_ppERK, polyOrder, windowSize, [], 1);

% Baseline correction
startRow = 150;
lastrow  = min(1400, size(smoothed_ppERK_1, 1));   % clamp so short profiles don't error
baseline_ppERK = min(smoothed_ppERK_1(startRow:lastrow, :), [], 1, 'omitnan');
smoothed_ppERK_corrected = smoothed_ppERK - baseline_ppERK;

%% Peak detection (median of a window around the max)
[m_1, n_1]      = size(smoothed_ppERK_corrected);
peak_ppERK_bcgd = zeros(1, n_1);
peak_ppERK_raw  = zeros(1, n_1);
window_size     = 150;

for col = 1:n_1
    column_data_ppERK     = sgolayfilt(smoothed_ppERK_corrected(:, col), polyOrder, windowSize, [], 1);
    column_data_ppERK_raw = sgolayfilt(smoothed_ppERK(:, col),           polyOrder, windowSize, [], 1);

    [~, max_index_ppERK] = max(column_data_ppERK);
    start_idx = max(1,   max_index_ppERK - floor(window_size / 2));
    end_idx   = min(m_1, max_index_ppERK + floor(window_size / 2));

    peak_ppERK_bcgd(col) = median(column_data_ppERK(start_idx:end_idx));
    peak_ppERK_raw(col)  = median(column_data_ppERK_raw(start_idx:end_idx));
end

peak_values_bcgd = peak_ppERK_bcgd';
writematrix(peak_values_bcgd, fullfile(parentDir, [parentFolderName, '_ppERK_peak_bcgd_values.csv']));

peak_values_raw = peak_ppERK_raw';
writematrix(peak_values_raw, fullfile(parentDir, [parentFolderName, '_ppERK_peak_raw_values.csv']));

%% Plots
mainFolder      = parentDir;
numColumns_ppERK = size(smoothed_ppERK, 2);
colorMap_ppERK   = turbo(numColumns_ppERK);

% Baseline-corrected ppERK
figure;
set(gcf, 'Position', [100, 100, 1.7 * 560, 1.7 * 420]);
set(gca, 'Color', [0.95, 0.95, 0.95]);
hold on;
for col = 1:numColumns_ppERK
    plot(sgolayfilt(smoothed_ppERK_corrected(:, col), polyOrder, windowSize, [], 1), ...
         'LineWidth', 1.5, 'Color', colorMap_ppERK(col, :));
end
hold off;
xlabel('Length (pixels)'); ylabel('Intensity (a.u)');
title('ppERK-smoothened-win=201-order=1');
legend(cleanedNames, 'Location', 'best'); grid on;
saveas(gcf, fullfile(mainFolder, sprintf('%s_Smoothed_Bcgd_ppERK.png', parentFolderName)));

% Raw (no baseline subtraction) ppERK
figure;
set(gcf, 'Position', [100, 100, 1.7 * 560, 1.7 * 420]);
set(gca, 'Color', [0.95, 0.95, 0.95]);
hold on;
for col = 1:numColumns_ppERK
    plot(sgolayfilt(smoothed_ppERK(:, col), polyOrder, windowSize, [], 1), ...
         'LineWidth', 1.5, 'Color', colorMap_ppERK(col, :));
end
hold off;
xlabel('Length (pixels)'); ylabel('Intensity (a.u)');
title('NoBcgd_ppERK-smoothened-win=201-order=1');
legend(cleanedNames, 'Location', 'best'); grid on;
saveas(gcf, fullfile(mainFolder, sprintf('%s_Smoothed_raw_ppERK.png', parentFolderName)));

%% Final combined (median / std / n across subfolders)
windowSize =9; polyOrder = 6;

final_ppERK_bgd(:, 1) = sgolayfilt(median(smoothed_ppERK_corrected, 2, 'omitnan'), polyOrder, windowSize, [], 1);
final_ppERK_bgd(:, 2) = std(smoothed_ppERK_corrected, 0, 2, 'omitnan');
final_ppERK_bgd(:, 3) = sum(~isnan(smoothed_ppERK_corrected), 2);
writematrix(final_ppERK_bgd, fullfile(parentDir, [parentFolderName, '_ppERK_final_bcgd_sub.csv']));

final_ppERK(:, 1) = sgolayfilt(median(smoothed_ppERK, 2, 'omitnan'), polyOrder, windowSize, [], 1);
final_ppERK(:, 2) = std(smoothed_ppERK, 0, 2, 'omitnan');
final_ppERK(:, 3) = sum(~isnan(smoothed_ppERK), 2);
writematrix(final_ppERK, fullfile(parentDir, [parentFolderName, '_ppERK_final_raw.csv']));
