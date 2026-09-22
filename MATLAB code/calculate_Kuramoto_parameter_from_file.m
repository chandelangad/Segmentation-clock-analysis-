% Prompt user to select a file
[fileName, filePath] = uigetfile({'*.xlsx;*.csv','Data Files (*.xlsx, *.csv)'}, 'Select the file containing phase values');
if isequal(fileName, 0)
    disp('No file selected. Exiting.');
    return;
end

fullFilePath = fullfile(filePath, fileName);

% Determine file extension
[~,~,ext] = fileparts(fileName);

% Load the phase data based on file type
if strcmpi(ext, '.csv')
    raw_data = readmatrix(fullFilePath);
elseif strcmpi(ext, '.xlsx')
    raw_data = readmatrix(fullFilePath);   % better than xlsread
else
    error('Unsupported file type. Please select a .csv or .xlsx file.');
end

% -------------------------------
% Remove first row (sample numbers)
% -------------------------------
phase_matrix = raw_data(2:end, :);

% Initialize output
[num_timepoints, num_tracks] = size(phase_matrix);
R = NaN(num_timepoints, 1);

% Loop through each time point
for t = 1:num_timepoints
    phases_at_t = phase_matrix(t, :);

    % Ignore NaNs
    valid_phases = phases_at_t(~isnan(phases_at_t));

    % Compute only if valid data exists
    if ~isempty(valid_phases)
        complex_exponentials = exp(1i * valid_phases);
        R(t) = abs(mean(complex_exponentials)); % cleaner than sum/length
    end
end

% -------------------------------
% Smooth Kuramoto parameter
% -------------------------------
windowSizeSG = 11;  
polyOrderSG = 1;    

% Ensure window size is odd and valid
if mod(windowSizeSG,2) == 0
    windowSizeSG = windowSizeSG + 1;
end

smoothed_R = sgolayfilt(R, polyOrderSG, windowSizeSG);

% -------------------------------
% Plot
% -------------------------------
figure;
plot(smoothed_R, 'o-', 'LineWidth', 2, 'MarkerSize', 6);
xlabel('Time Point');
ylabel('Kuramoto Parameter R');
title('Kuramoto Parameter R as a function of Time');
grid on;

% -------------------------------
% Save results
% -------------------------------
output_file = fullfile(filePath, 'kuramoto_parameter_results.csv');

% Save both raw and smoothed
output_matrix = [R smoothed_R];
writematrix(output_matrix, output_file);

disp('Saved Kuramoto results (raw and smoothed).');