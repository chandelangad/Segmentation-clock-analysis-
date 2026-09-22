clear all;
% Prompt user to select the parent folder
parentDir = uigetdir('', 'Select the parent folder');

% Check if a directory was selected
if parentDir == 0
    disp('No folder selected. Exiting...');
    return;
end

% Extract the name of the parent folder
[parentPath, parentFolderName, ~] = fileparts(parentDir);

% Get all subfolders in the parent directory
subfolders = dir(parentDir);

% Filter out non-folder entries and keep valid subfolder names
subfolders = subfolders([subfolders.isdir] & ~startsWith({subfolders.name}, '.'));

% Initialize variables to store the aggregated results
Avg_ppERK = [];
Avg_bcat = [];
Avg_Her7V = [];

% Variable to track maximum rows across all subfolders
maxRows = 0;

% Initialize a cell array to store subfolder names
subfolderNames = {};

% Loop through each subfolder in the parent directory
for i = 1:length(subfolders)
    % Save the subfolder name in the array as the loop iterates
    subfolderNames{i} = subfolders(i).name;

    % Construct the full subfolder path
    subfolderPath = fullfile(parentDir, subfolders(i).name);

    % Locate the "Her7Venus_ppERK_Bcat" subfolder
    targetSubfolder = fullfile(subfolderPath, 'Her7Venus_ppERK_Bcat');
    if ~isfolder(targetSubfolder)
        disp(['Skipping folder: ', subfolders(i).name, ' (No Her7Venus_ppERK_Bcat subfolder)']);
        continue;
    end

    % Process CSV files within the target subfolder
    filePattern = fullfile(targetSubfolder, '*.csv');
    files = dir(filePattern);

    % Check if there are CSV files in the folder
    if isempty(files)
        disp(['No CSV files found in folder: ', targetSubfolder]);
        continue;
    end

    % Initialize a temporary matrix for this subfolder
    tempMatrix = [];

    % Process each CSV file in the current subfolder
    for j = 1:length(files)
        % Get the full file name
        fileName = fullfile(targetSubfolder, files(j).name);

        % Read the CSV file
        T = readtable(fileName);

        % Extract the column data (assuming 'periods' column is in 2nd position)
        periodData = T{:, 2};

        % Append data to the temporary matrix
        tempMatrix = [tempMatrix, periodData]; %#ok<AGROW> Avoid in large data; preallocation better
    end

    % Update maximum rows
    maxRows = max(maxRows, size(tempMatrix, 1));

    % Combine temporary matrix with finalMatrix
    if ~exist('finalMatrix', 'var') || isempty(finalMatrix)
        finalMatrix = tempMatrix;
    else
        % Adjust for differing row lengths by padding with NaN
        rowsToPad = max(size(finalMatrix, 1), size(tempMatrix, 1));
        finalMatrix = [finalMatrix; NaN(rowsToPad - size(finalMatrix, 1), size(finalMatrix, 2))];
        tempMatrix = [tempMatrix; NaN(rowsToPad - size(tempMatrix, 1), size(tempMatrix, 2))];
        finalMatrix = [finalMatrix, tempMatrix];
    end

    % Process data for the current subfolder
    j = size(tempMatrix, 2) / 7; % Assuming the data matrix structure is consistent

    abody_val_ppERK = zeros(size(tempMatrix, 1), j); % Preallocate matrix
    abody_val_bcat = zeros(size(tempMatrix, 1), j);
    abody_val_nuc_Her7V = zeros(size(tempMatrix, 1), j);

    for k = 1:j
        abody_val_ppERK(:, k) = tempMatrix(:, 5*j + k) ./ tempMatrix(:, 2*j + k); % ppERK ratio
        abody_val_bcat(:, k) = tempMatrix(:, 3*j + k) ./ tempMatrix(:, 2*j + k); % Bcat ratio
        abody_val_nuc_Her7V(:, k) = tempMatrix(:, 4*j + k) ./ tempMatrix(:, 2*j + k);
    end

    % Resize Avg matrices dynamically to handle varying rows
    if size(Avg_ppERK, 1) < maxRows
        Avg_ppERK = [Avg_ppERK; NaN(maxRows - size(Avg_ppERK, 1), size(Avg_ppERK, 2))];
        Avg_bcat = [Avg_bcat; NaN(maxRows - size(Avg_bcat, 1), size(Avg_bcat, 2))];
        Avg_Her7V = [Avg_Her7V; NaN(maxRows - size(Avg_Her7V, 1), size(Avg_Her7V, 2))];
    end

    % Append averages incrementally
    Avg_ppERK(1:size(abody_val_ppERK, 1), i) = mean(abody_val_ppERK, 2, 'omitnan'); % Mean ppERK
    Avg_bcat(1:size(abody_val_bcat, 1), i) = mean(abody_val_bcat, 2, 'omitnan'); % Mean Bcat
    Avg_nuc_Her7V(1:size(abody_val_nuc_Her7V, 1), i) = mean(abody_val_nuc_Her7V, 2, 'omitnan');
    Avg_Her7V(1:size(tempMatrix, 1), i) = tempMatrix(:, j+1); % First column as a reference
end

% Cleaned subfolder names
cleanedNames = cell(size(subfolderNames)); % Preallocate cell array
for i = 1:length(subfolderNames)
    % Extract the part before '_Her7Venus' and the last number
    parts = split(subfolderNames{i}, '_');
    prefix = parts{1}; % '5mincontrol'
    
    % Extract the trailing number using regular expression
    trailingNum = regexp(subfolderNames{i}, '_\d+', 'match'); % Find '_1', '_2', etc.
    trailingNum = strrep(trailingNum{end}, '_', ''); % Remove the underscore
    
    % Combine cleaned parts
    cleanedNames{i} = sprintf('%s-%s', prefix, trailingNum); % '5mincontrol-1'
end


%% 
% Define Savitzky-Golay filter parameters
windowSize = 101; % Odd number (100 neighbors on each side + 1)
polyOrder = 6; % Polynomial order for smoother curves

% Apply Savitzky-Golay filter to each column of the Avg matrices
smoothed_ppERK = sgolayfilt(Avg_ppERK, polyOrder, windowSize, [], 1);
smoothed_bcat = sgolayfilt(Avg_bcat, polyOrder, windowSize, [], 1);
smoothed_Her7V = sgolayfilt(Avg_Her7V, polyOrder, windowSize, [], 1);
smoothed_nuc_Her7V = sgolayfilt(Avg_nuc_Her7V, polyOrder, windowSize, [], 1);

% Define Savitzky-Golay filter parameters
windowSize = 201; % Odd number (100 neighbors on each side + 1)
polyOrder = 1; % Polynomial order for smoother curves

% Extra smoothening jsut to get the baseline value and for plotting 
smoothed_ppERK_1 = sgolayfilt(Avg_ppERK, polyOrder, windowSize, [], 1);
smoothed_bcat_1 = sgolayfilt(Avg_bcat, polyOrder, windowSize, [], 1);
smoothed_Her7V_1 = sgolayfilt(Avg_Her7V, polyOrder,windowSize, [], 1);
smoothed_nuc_Her7V_1 = sgolayfilt(Avg_nuc_Her7V, polyOrder,windowSize, [], 1);

% Baseline correction
startRow = 150; % Starting row for baseline computation
lastrow = 1400;
baseline_ppERK = min(smoothed_ppERK_1(startRow:lastrow, :), [], 1, 'omitnan'); % Minimum from row 400 onward
smoothed_ppERK_corrected = smoothed_ppERK - baseline_ppERK;

baseline_bcat = min(smoothed_bcat_1(startRow:lastrow, :), [], 1, 'omitnan'); % Minimum from row 400 onward
smoothed_bcat_corrected = smoothed_bcat - baseline_bcat;
% Assuming smoothed_bcat_corrected is your mxn matrix

baseline_Her7V = min(smoothed_Her7V_1(startRow:end, :), [], 1, 'omitnan'); % Minimum from row 400 onward
smoothed_Her7V_corrected = smoothed_Her7V - baseline_Her7V;

baseline_nuc_Her7V = min(smoothed_nuc_Her7V_1(startRow:end, :), [], 1, 'omitnan'); % Minimum from row 400 onward
smoothed_nuc_Her7V_corrected = smoothed_nuc_Her7V - baseline_nuc_Her7V;


[m_1, n_1] = size(smoothed_bcat_corrected);
peak_ppERK_bcgd = zeros(1, n_1);
peak_bcat_bcgd = zeros(1, n_1);
peak_ppERK_raw = zeros(1, n_1);
peak_bcat_raw = zeros(1, n_1);

% Define the window size for taking median value of the peak
window_size = 150;

for col = 1:n_1
    % Get the current column
    column_data_ppERK =sgolayfilt(smoothed_ppERK_corrected(:, col), polyOrder,windowSize, [], 1);
    column_data_bcat = sgolayfilt(smoothed_bcat_corrected(:, col), polyOrder,windowSize, [], 1);
    column_data_ppERK_raw =sgolayfilt(smoothed_ppERK(:, col), polyOrder,windowSize, [], 1);
    column_data_bcat_raw = sgolayfilt(smoothed_bcat(:, col), polyOrder,windowSize, [], 1);
    
    % Find the index of the maximum value
    [~, max_index_ppERK] = max(column_data_ppERK);
    [~, max_index_bcat] = max(column_data_bcat);



    % Determine the window boundaries
    start_idx_ppERK = max(1, max_index_ppERK - floor(window_size / 2));
    end_idx_ppERK = min(m_1, max_index_ppERK + floor(window_size / 2));
    start_idx_bcat = max(1, max_index_bcat - floor(window_size / 2));
    end_idx_bcat = min(m_1, max_index_bcat + floor(window_size / 2));
    
    
    % Extract the window and compute the median
    window_data_ppERK = column_data_ppERK(start_idx_ppERK:end_idx_ppERK);
    peak_ppERK_bcgd(col) = median(window_data_ppERK);
    window_data_ppERK_raw = column_data_ppERK_raw(start_idx_ppERK:end_idx_ppERK);
    peak_ppERK_raw(col) = median(window_data_ppERK_raw);


    window_data_bcat = column_data_bcat(start_idx_bcat:end_idx_bcat);
    peak_bcat_bcgd(col) = median(window_data_bcat);
    window_data_bcat_raw = column_data_bcat_raw(start_idx_bcat:end_idx_bcat);
    peak_bcat_raw(col) = median(window_data_bcat_raw);
    

end

 peak_bcgd_ppERK = peak_ppERK_bcgd';
 peak_bcgd_bcat =  peak_bcat_bcgd';
 peak_raw_ppERK = peak_ppERK_raw';
 peak_raw_bcat =  peak_bcat_raw';


peak_values_bcgd = [peak_bcgd_ppERK, peak_bcgd_bcat];
csvFileName = fullfile(parentDir, [parentFolderName, '_peak_bcgd_values.csv']);
writematrix(peak_values_bcgd, csvFileName);
peak_values_raw = [peak_raw_ppERK, peak_raw_bcat];
csvFileName = fullfile(parentDir, [parentFolderName, '_peak_raw_values.csv']);
writematrix(peak_values_raw, csvFileName);

%% 

% Plot baseline-corrected smoothed_ppERK
figure;
set(gcf,'Position',  [100, 100, 1.7 * 560, 1.7 * 420])
set(gca, 'Color', [0.95, 0.95, 0.95]); % Light gray background
numColumns_ppERK = size(smoothed_ppERK_1, 2);
colorMap_ppERK = turbo(numColumns_ppERK);
hold on;
for col = 1:numColumns_ppERK
    plot(sgolayfilt(smoothed_ppERK_corrected(:, col), polyOrder, windowSize, [], 1), ...
         'LineWidth', 1.5, 'Color',colorMap_ppERK(col, :));
end
hold off;
xlabel('Length (pixels)');
ylabel('Intensity (a.u)');
title('ppERK-smoothened-win=201-order=1');
legend(cleanedNames, 'Location', 'best'); % Use subfolder names for the legend
grid on;

mainFolder = parentDir; % Parent folder selected earlier
fileName = sprintf('%s_Smoothed_Bcgd_ppERK.png', parentFolderName);
saveas(gcf, fullfile(mainFolder, fileName));

% Plot baseline-corrected smoothed_bcat
figure;
set(gcf, 'Position', [100, 100, 1.7 * 560, 1.7 * 420])
set(gca, 'Color', [0.95, 0.95, 0.95]); % Light gray background
hold on;
for col = 1:numColumns_ppERK
    plot(sgolayfilt(smoothed_bcat_corrected(:, col), polyOrder, windowSize, [], 1), ...
         'LineWidth', 1.5, 'Color', colorMap_ppERK(col, :));
end
hold off;
xlabel('Length (pixels)');
ylabel('Intensity (a.u)');
title('B-cat-smoothened-win=201-order=1');
legend(cleanedNames, 'Location', 'best'); % Use subfolder names for the legend
grid on;

fileName = sprintf('%s_Smoothed_Bcgd_b-cat.png', parentFolderName);
saveas(gcf, fullfile(mainFolder, fileName));


% Plot smoothed_Her7V psoterior aligned
figure;
set(gcf, 'Position', [100, 100, 1.7 * 560, 1.7 * 420]); % Adjust the width (560) and height (420)
set(gca, 'Color', [0.95, 0.95, 0.95]); % Light gray background
hold on;
for col = 1:numColumns_ppERK
    plot(sgolayfilt(smoothed_Her7V_corrected(:, col), polyOrder, 181, [], 1), ...
         'LineWidth', 2.5, 'Color', colorMap_ppERK(col, :));
end
hold off;
xlabel('Length (pixels)');
ylabel('Intensity (a.u)');
title('clock-smoothened-win=251-order=1');
legend(cleanedNames, 'Location', 'best'); % Use subfolder names for the legend
legend boxoff;
grid on;


fileName = sprintf('%s_Smoothed_Bcgd_Clock.png', parentFolderName);
saveas(gcf, fullfile(mainFolder, fileName));

% Plot smoothed_nuc_Her7V psoterior aligned
figure;
set(gcf, 'Position', [100, 100, 1.7 * 560, 1.7 * 420]); % Adjust the width (560) and height (420)
set(gca, 'Color', [0.95, 0.95, 0.95]); % Light gray background
hold on;
for col = 1:numColumns_ppERK
    plot(sgolayfilt(smoothed_nuc_Her7V_corrected(:, col), polyOrder, 181, [], 1), ...
         'LineWidth', 2.5, 'Color', colorMap_ppERK(col, :));
end
hold off;
xlabel('Length (pixels)');
ylabel('Intensity (a.u)');
title('clock-smoothened-win=251-order=1');
legend(cleanedNames, 'Location', 'best'); % Use subfolder names for the legend
legend boxoff;
grid on;


fileName = sprintf('%s_Smoothed_Bcgd_Clock-Nuc.png', parentFolderName);
saveas(gcf, fullfile(mainFolder, fileName));


close(gcf);
close(gcf);
close(gcf);
close(gcf);

%% 
%%%%%%%%%%%%%%%%%%%%  No Bcgd subtracted graphs%%%%%%
% Plot baseline-corrected smoothed_ppERK
figure;
set(gcf,'Position',  [100, 100, 1.7 * 560, 1.7 * 420])
set(gca, 'Color', [0.95, 0.95, 0.95]); % Light gray background
numColumns_ppERK = size(smoothed_ppERK_1, 2);
colorMap_ppERK = turbo(numColumns_ppERK);
hold on;
for col = 1:numColumns_ppERK
    plot(sgolayfilt(smoothed_ppERK(:, col), polyOrder, windowSize, [], 1), ...
         'LineWidth', 1.5, 'Color',colorMap_ppERK(col, :));
end
hold off;
xlabel('Length (pixels)');
ylabel('Intensity (a.u)');
title('NoBcgd_ppERK-smoothened-win=201-order=1');
legend(cleanedNames, 'Location', 'best'); % Use subfolder names for the legend
grid on;

mainFolder = parentDir; % Parent folder selected earlier
fileName = sprintf('%s_Smoothed_raw_ppERK.png', parentFolderName);
saveas(gcf, fullfile(mainFolder, fileName));

% Plot baseline-corrected smoothed_bcat
figure;
set(gcf, 'Position', [100, 100, 1.7 * 560, 1.7 * 420])
set(gca, 'Color', [0.95, 0.95, 0.95]); % Light gray background
hold on;
for col = 1:numColumns_ppERK
    plot(sgolayfilt(smoothed_bcat(:, col), polyOrder, windowSize, [], 1), ...
         'LineWidth', 1.5, 'Color', colorMap_ppERK(col, :));
end
hold off;
xlabel('Length (pixels)');
ylabel('Intensity (a.u)');
title('B-cat-NoBcgd-smoothened-win=201-order=1');
legend(cleanedNames, 'Location', 'best'); % Use subfolder names for the legend
grid on;

fileName = sprintf('%s_Smoothed_raw_b-cat.png', parentFolderName);
saveas(gcf, fullfile(mainFolder, fileName));


% Plot smoothed_Her7V psoterior aligned
figure;
set(gcf, 'Position', [100, 100, 1.7 * 560, 1.7 * 420]); % Adjust the width (560) and height (420)
set(gca, 'Color', [0.95, 0.95, 0.95]); % Light gray background
hold on;
for col = 1:numColumns_ppERK
    plot(sgolayfilt(smoothed_Her7V(:, col), polyOrder, 251, [], 1), ...
         'LineWidth', 2.5, 'Color', colorMap_ppERK(col, :));
end
hold off;
xlabel('Length (pixels)');
ylabel('Intensity (a.u)');
title('clock-NoBcgd-smoothened-win=251-order=1');
legend(cleanedNames, 'Location', 'best'); % Use subfolder names for the legend
legend boxoff;
grid on;


fileName = sprintf('%s_Smoothed_raw_Clock.png', parentFolderName);
saveas(gcf, fullfile(mainFolder, fileName));
close(gcf);
close(gcf);
close(gcf);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 

%%%%%%%%%%%%%Anterior Aligned%%%%%%%%%%%%%%%

% 
% A= flipud(smoothed_Her7V_corrected);
% 
% [m, n] = size(A);
% Ant_smoothed_Her7V_corrected = NaN(m, n); % Preallocate new matrix
% for col = 1:n
%     nonNaNValues = A(~isnan(A(:, col)), col); % Extract non-NaN values
%     Ant_smoothed_Her7V_corrected(1:length(nonNaNValues), col) = nonNaNValues; % Fill the column in B
% end
% 
% 
% figure;
% set(gcf, 'Position', [100, 100, 1.7 * 560, 1.7 * 420]); % Adjust the width (560) and height (420)
% set(gca, 'Color', [0.95, 0.95, 0.95]); % Light gray background
% hold on;
% for col = 1:numColumns_ppERK
%     plot(sgolayfilt(Ant_smoothed_Her7V_corrected(:, col), polyOrder, windowSize, [], 1), ...
%          'LineWidth', 2.5, 'Color', colorMap_ppERK(col, :));
% end
% hold off;
% xlabel('Length (pixels)');
% ylabel('Intensity (a.u)');
% title('Ant-algined-clock-smoothened-win=201-order=1');
% legend(cleanedNames, 'Location', 'best'); % Use subfolder names for the legend
% legend boxoff;
% grid on;
% 
% 
% fileName = sprintf('%s_AntAligned_Smoothed_Bcgd_Clock.png', parentFolderName);
% saveas(gcf, fullfile(mainFolder, fileName));





%% 

% Final values are average of smoothened individual window
windowSize = 101; 
polyOrder = 3; 

final_ppERK_bgd(:, 1) = sgolayfilt(median(smoothed_ppERK_corrected, 2, 'omitnan'), polyOrder, windowSize, [], 1); % Median
final_ppERK_bgd(:, 2) = std(smoothed_ppERK_corrected, 0, 2, 'omitnan'); 
final_ppERK_bgd(:, 3) = sum(~isnan(smoothed_ppERK_corrected), 2); 


final_bcat_bgd(:, 1) = sgolayfilt(median(smoothed_bcat_corrected, 2, 'omitnan'), polyOrder, windowSize, [], 1); % Median
final_bcat_bgd(:, 2) = std(smoothed_bcat_corrected, 0, 2, 'omitnan');
final_bcat_bgd(:, 3) = sum(~isnan(smoothed_bcat_corrected), 2); 

final_Her7V_bgd(:, 1) = sgolayfilt(median(smoothed_Her7V_corrected, 2, 'omitnan'), 6, 101, [], 1); 
final_Her7V_bgd(:, 2) = std(smoothed_Her7V_corrected, 0, 2, 'omitnan'); 
final_Her7V_bgd(:, 3) = sum(~isnan(smoothed_Her7V_corrected), 2); 


final_combined_bcgd_sub = [final_ppERK_bgd, final_bcat_bgd, final_Her7V_bgd];
csvFileName = fullfile(parentDir, [parentFolderName, '_final_combined_bcgd_sub.csv']);
writematrix(final_combined_bcgd_sub, csvFileName);
% 
% [pks_ppERK, peak_xval_ppERK] = max(final_ppERK_bgd(:, 1));
% peak_ppERK = median(smoothed_ppERK_corrected((peak_xval_ppERK-75:peak_xval_ppERK+75),:,1));
% peak_ppERK = peak_ppERK';
% 
% [pks_bcat, peak_xval_bcat] = max(final_bcat_bgd(:, 1));
% peak_bcat = median(smoothed_bcat_corrected((peak_xval_bcat-75:peak_xval_bcat+75),:,1));
% peak_bcat = peak_bcat';
% 
% peak_values = [peak_ppERK, peak_bcat];
% csvFileName = fullfile(parentDir, [parentFolderName, '_peak_bcgd_values.csv']);
% writematrix(peak_values, csvFileName);

% peak_xval_Her7V = 425; 
% peak_Her7V = median(smoothed_Her7V_corrected((peak_xval_Her7V-75:peak_xval_Her7V+75),:,1));
% peak_Her7V = peak_Her7V';
% 
% csvFileName = fullfile(parentDir, [parentFolderName, '_peak_bcgd_Her7V-pPSM_values.csv']);
% writematrix(peak_Her7V, csvFileName);
%% 

%%%%%%%%%%%%%%%%%%%%%%%%%%%%  Raw Value   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Define Savitzky-Golay filter parameters
windowSize = 101; % Odd number (100 neighbors on each side + 1)
polyOrder = 3; % Polynomial order for smoother curves

% Calculate the final averages across all columns
% Compute the median, standard deviation, and number of samples for smoothed_ppERK
final_ppERK(:, 1) = sgolayfilt(median(smoothed_ppERK, 2, 'omitnan'), polyOrder, windowSize, [], 1); % Median
final_ppERK(:, 2) = std(smoothed_ppERK, 0, 2, 'omitnan'); % Standard deviation
final_ppERK(:, 3) = sum(~isnan(smoothed_ppERK), 2); % Number of non-NaN samples

% Compute the median, standard deviation, and number of samples for smoothed_bcat
final_bcat(:, 1) = sgolayfilt(median(smoothed_bcat, 2, 'omitnan'), polyOrder, windowSize, [], 1); % Median
final_bcat(:, 2) = std(smoothed_bcat, 0, 2, 'omitnan'); % Standard deviation
final_bcat(:, 3) = sum(~isnan(smoothed_bcat), 2); % Number of non-NaN samples

% Compute the median, standard deviation, and number of samples for smoothed_Her7V
final_Her7V(:, 1) = sgolayfilt(median(smoothed_Her7V, 2, 'omitnan'), 6, 101, [], 1); % Median
final_Her7V(:, 2) = std(smoothed_Her7V, 0, 2, 'omitnan'); % Standard deviation
final_Her7V(:, 3) = sum(~isnan(smoothed_Her7V), 2); % Number of non-NaN samples

% Combine all columns into final_combined
final_combined_raw = [final_ppERK, final_bcat, final_Her7V];
% Specify the file path in the parent directory
% Construct the CSV file name
csvFileName = fullfile(parentDir, [parentFolderName, '_final_combined_raw.csv']);
% Save the combined matrix as a CSV file
writematrix(final_combined_raw, csvFileName);

% [pks_ppERK_raw, peak_xval_ppERK_raw] = max(final_ppERK(:, 1));
% peak_ppERK_raw = median(smoothed_ppERK((peak_xval_ppERK_raw-75:peak_xval_ppERK_raw+75),:,1));
% peak_ppERK_raw = peak_ppERK_raw';
% 
% [pks_bcat_raw, peak_xval_bcat_raw] = max(final_bcat(1:1000, 1));
% peak_bcat_raw = median(smoothed_bcat((peak_xval_bcat_raw-75:peak_xval_bcat_raw+75),:,1));
% peak_bcat_raw = peak_bcat_raw';
% 
% peak_values_raw = [peak_ppERK_raw , peak_bcat_raw];
% csvFileName = fullfile(parentDir, [parentFolderName, '_peak_raw_values.csv']);
% writematrix(peak_values_raw, csvFileName);
% 
% peak_xval_Her7V = 425; 
% peak_Her7V_raw = median(smoothed_Her7V((peak_xval_Her7V-75:peak_xval_Her7V+75),:,1));
% peak_Her7V_raw = peak_Her7V_raw';
% 
% csvFileName = fullfile(parentDir, [parentFolderName, '_peak_raw_Her7V-pPSM_values.csv']);
% writematrix(peak_Her7V_raw, csvFileName);

%% 


% % Optional: Plot the smoothed averages
% figure;
% subplot(3, 1, 1);
% plot(final_ppERK(:, 1), 'LineWidth', 1.5);
% title('Smoothed Avg\_ppERK');
% xlabel('Length (Um)');
% ylabel('Intensity (a.u)');
% 
% subplot(3, 1, 2);
% plot(final_bcat(:, 1), 'LineWidth', 1.5);
% title('Smoothed Avg\_bcat');
% xlabel('Length (Um)');
% ylabel('Intensity (a.u)');
% 
% subplot(3, 1, 3);
% plot(final_Her7V(:, 1), 'LineWidth', 1.5);
% title('Smoothed Avg\_Her7V');
% xlabel('Length (Um)');
% ylabel('Intensity (a.u)');

% Save the figure in the main folder
% mainFolder = parentDir; % Parent folder selected earlier
% saveas(gcf, fullfile(mainFolder, 'Smoothed_Avg_Plots.png')); % Save figure as PNG