% Prompt user to select the file containing the signals (any file format)
clear all;
[fileName, filePath] = uigetfile('*.*', 'Select the file containing the oscillatory signals');
if fileName == 0
    disp('No file selected. Exiting script.');
    return;
end

% Determine file extension and read data accordingly
[~, ~, ext] = fileparts(fileName);

% Read the data based on the file type
switch ext
    case {'.csv', '.txt'}
        % Load data from CSV or TXT file
        signals = readmatrix(fullfile(filePath, fileName));
    case {'.xlsx', '.xls'}
        % Load data from XLSX file
        signals = readmatrix(fullfile(filePath, fileName));
    case {'.mat'}
        % Load data from MAT file
        temp = load(fullfile(filePath, fileName));
        % Assuming the signal variable is named 'signals' in the .mat file
        signals = temp.signals;
    otherwise
        disp('Unsupported file type. Exiting script.');
        return;
end

% Ensure data is in the correct format: rows are timepoints and columns are signals
if size(signals, 1) < size(signals, 2)
    signals = signals';
end

% Split the signals into oscillatory and ERK values
numColumns = size(signals, 2);  % Get the number of columns
halfColumns = floor(numColumns / 2);  % Assuming even number of columns

% First half columns are oscillatory signals, second half are ERK values
oscillatorySignals = signals(:, 1:halfColumns);
ERK_values = signals(:, halfColumns+1:end);  % Corresponding ERK values

% Initialize matrices to store the amplitudes, and time positions of peaks and troughs
numSignals = size(oscillatorySignals, 2);  % Number of signals (columns)
cycleAmplitudes = zeros(numSignals, 1000);  % Assuming maximum 1000 cycles per signal, adjust if needed
maxTimePositions = zeros(numSignals, 1000); % Store time positions of local maxima
minTimePositions = zeros(numSignals, 1000); % Store time positions of local minima
A = zeros(numSignals, 1000);  % Store merged time positions for each signal
newMatrix = zeros(numSignals, 1000);  % Store mean of consecutive values for each signal
normalizedAmplitudes = zeros(numSignals, 1000);  % Store normalized amplitudes for each signal


% Loop through each signal (column) to calculate the amplitudes for all cycles
for i = 1:numSignals
    signal = oscillatorySignals(:, i);  % Extract the signal for the current TrackID
    
    % Apply Savitzky-Golay smoothing (default parameters)
    windowSizeSG = 5;  % Window size for smoothing (adjustable)
    polyOrderSG = 3;    % Polynomial order for smoothing (adjustable)
    smoothedSignal = sgolayfilt(signal, polyOrderSG, windowSizeSG);  % Smooth the signal
     % smoothedSignal =oscillatorySignals(:, i);  
    
    % Find the local maxima and minima on the smoothed signal
    [maxPeaks, maxLocs] = findpeaks(smoothedSignal);  % Find local maxima
    [minPeaks, minLocs] = findpeaks(-smoothedSignal);  % Find local minima (invert signal to use findpeaks)
    minPeaks = -minPeaks;  % Revert the inversion for proper min values
    
    % Store the time positions of the maxima and minima
    maxTimePositions(i, 1:length(maxLocs)) = maxLocs;  % Store the time indices of maxima
    minTimePositions(i, 1:length(minLocs)) = minLocs;  % Store the time indices of minima
    
    % Combine maxima and minima into one array for the entire signal
    allPeaks = sort([maxLocs; minLocs]);

    % Calculate the amplitude for each cycle (peak-to-peak)
    cycleAmp = [];
    for j = 1:length(allPeaks)-1
        % Ensure valid indexing by checking bounds
        if allPeaks(j) > length(signal) || allPeaks(j+1) > length(signal)
            continue;  % Skip invalid indices
        end
        
        cycleData = signal(allPeaks(j):allPeaks(j+1));  % Get signal data between two peaks
        cycleAmp = [cycleAmp; max(cycleData) - min(cycleData)];  % Calculate peak-to-peak amplitude for the cycle
    end
    
    % Remove zeros from cycle amplitudes
    cycleAmp = cycleAmp(cycleAmp ~= 0);  % Remove zeros

    % Store the calculated amplitudes for the current signal
    cycleAmplitudes(i, 1:length(cycleAmp)) = cycleAmp;  % Store amplitudes in matrix
    
    % Store the merged and sorted time positions (max and min) in A
    A(i, 1:length(allPeaks)) = allPeaks;  % Store in A for each signal
    
    % Create a new matrix with the mean of consecutive values for each column of A
    mergedTimes = A(i, 1:length(allPeaks));  % Get merged time positions for the current signal
    meanValues = [];

    % Calculate the mean of consecutive values for each column of A
    for j = 1:length(mergedTimes)-1
        meanValues = [meanValues; mean(mergedTimes(j:j+1))];  % Calculate mean of consecutive values
    end
    newMatrix(i, 1:length(meanValues)) = meanValues;  % Store the calculated mean values in the matrix

    % Normalize the amplitude by dividing each cycle amplitude by the first amplitude of the cycle
    firstAmplitude = cycleAmp(1);  % First amplitude for normalization
    normalizedAmp = cycleAmp / firstAmplitude;  % Normalize the amplitudes
    
    % Remove zeros from normalized amplitudes
    normalizedAmp = normalizedAmp(normalizedAmp ~= 0);  % Remove zeros

    % Store the normalized amplitudes
    normalizedAmplitudes(i, 1:length(normalizedAmp)) = normalizedAmp;  % Store the normalized amplitudes
end


% Plotting the raw and smoothed oscillatory signals for each track
figure;
hold on;

for i = 1:numSignals
    % Extract the oscillatory signal for the current TrackID
    signal = oscillatorySignals(:, i);
    
    % Apply Savitzky-Golay smoothing
    windowSizeSG = 11;  % Window size for smoothing (adjustable)
    polyOrderSG = 3;   % Polynomial order for smoothing (adjustable)clear a
    smoothedSignal = sgolayfilt(signal, polyOrderSG, windowSizeSG);  % Smoothed signal

    % Plot the raw signal for the current TrackID
    plot(1:length(signal), signal, '-o', 'DisplayName', ['Raw Signal TrackID ' num2str(i)], 'LineWidth', 1.5);
    
    % Plot the smoothed signal for the current TrackID
    plot(1:length(smoothedSignal), smoothedSignal, '-x', 'DisplayName', ['Smoothed Signal TrackID ' num2str(i)], 'LineWidth', 1.5);
end

hold off;
xlabel('Time');
ylabel('Signal Amplitude');
title('Raw and Smoothed Oscillatory Signals for Each Track');
legend('show');
grid on;

% Display the plot
disp('Raw and Smoothed Oscillatory Signals plotting complete.');


% ** New functionality added for ERK values **

% Store the ERK values in a new matrix
ERK_values_matrix = ERK_values;

% Convert the newMatrix (Amp_timepoints) to integer values
Amp_timepoints = round(newMatrix);  % Convert time points to integer values

% Create a new matrix 'ERK_values_at_Amp' for ERK values corresponding to timepoints in Amp_timepoints
ERK_values_at_Amp = NaN(size(Amp_timepoints));  % Initialize with NaN
for i = 1:numSignals
    for j = 1:length(Amp_timepoints)
        if ~isnan(Amp_timepoints(i, j))  % Only if there's a valid timepoint
            % Ensure timepoint is a valid index within the range of ERK_values_matrix
            timepoint = Amp_timepoints(i, j);
            if timepoint > 0 && timepoint <= size(ERK_values_matrix, 1)  % Check if timepoint is valid
                % Ensure the column index 'i' is within bounds for ERK_values_matrix
                if i <= size(ERK_values_matrix, 2)
                    ERK_values_at_Amp(i, j) = ERK_values_matrix(timepoint, i);  % Store ERK value
                else
                    % Handle the case where 'i' exceeds the number of columns in ERK_values_matrix
                    ERK_values_at_Amp(i, j) = NaN;  % Assign NaN if out of bounds
                    disp(['Warning: TrackID ', num2str(i), ' exceeds number of ERK value columns.']);
                end
            else
                % If the timepoint is out of range, leave as NaN (or handle as needed)
                ERK_values_at_Amp(i, j) = NaN;
                disp(['Warning: Timepoint ', num2str(timepoint), ' is out of range for TrackID ', num2str(i)]);
            end
        end
    end
end


% Create 'median_ERK_val_at_Amp' with median and standard deviation across columns
% Create 'median_ERK_val_at_Amp' with median and standard deviation across columns
median_ERK_val_at_Amp = NaN(size(ERK_values_at_Amp, 2), 2);  % Two columns: median and std
for i = 1:size(ERK_values_at_Amp, 2)
    % Calculate the median and standard deviation for each cycle across all tracks (rows)
    median_ERK_val_at_Amp(i, 1) = median(ERK_values_at_Amp(:, i), 'omitnan');  % Median of ERK values, ignoring NaNs
    median_ERK_val_at_Amp(i, 2) = std(ERK_values_at_Amp(:, i), 'omitnan');    % Standard deviation, ignoring NaNs
end

% Display 'median_ERK_val_at_Amp'
disp('Median and Standard Deviation of ERK values at Amp timepoints:');
disp(median_ERK_val_at_Amp);

cycleAmplitudes(cycleAmplitudes==0) =NaN;
normalizedAmplitudes(normalizedAmplitudes==0) =NaN;

% Plotting the calculated cycle amplitudes for each signal on one graph
figure;
hold on;

for i = 1:numSignals
    cycleAmp = cycleAmplitudes(i, :);  % Get the cycle amplitudes for the current signal
    plot(1:length(cycleAmp), cycleAmp, '-o', 'DisplayName', ['TrackID ' num2str(i)]);
end

hold off;
xlabel('Cycle Number');
ylabel('Amplitude');
title('Amplitude of Each Cycle for All TrackIDs');
legend('show');

% Display the plot
disp('Cycle amplitudes plotting complete.');

% Plotting amplitude vs time (mean of consecutive values from newMatrix)
figure;
hold on;

for i = 1:numSignals
    % For each signal, plot the amplitude vs the mean of consecutive values
    cycleAmp = cycleAmplitudes(i, :);  % Get the amplitudes for the current signal
    newMatrixColumn = newMatrix(i, :); % Get the corresponding new matrix for the current signal
    
    % Plot amplitude vs. the mean values of the merged time positions (new matrix)
    plot(newMatrixColumn, cycleAmp, '-o', 'DisplayName', ['TrackID ' num2str(i)]);
end

hold off;
xlabel('Mean of Consecutive Time Positions');
ylabel('Amplitude');
title('Amplitude vs Time (Mean of Consecutive Time Positions)');
legend('show');
grid on;

% Display the plot
disp('Amplitude vs Time (Mean of Consecutive Time Positions) plotting complete.');

% Plotting normalized amplitude vs time (mean of consecutive values from newMatrix)
figure;
hold on;

for i = 1:numSignals
    % For each signal, plot the normalized amplitude vs the mean of consecutive values
    normalizedAmp = normalizedAmplitudes(i, :);  % Get the normalized amplitudes for the current signal
    newMatrixColumn = newMatrix(i, :);  % Get the corresponding new matrix for the current signal
    
    % Plot normalized amplitude vs. the mean values of the merged time positions (new matrix)
    plot(newMatrixColumn, normalizedAmp, '-o', 'DisplayName', ['TrackID ' num2str(i)]);
end

hold off;
xlabel('Mean of Consecutive Time Positions');
ylabel('Normalized Amplitude');
title('Normalized Amplitude vs Time (Mean of Consecutive Time Positions)');
legend('show');
grid on;

% Display the plot
disp('Normalized Amplitude vs Time plotting complete.');

% Calculate median and standard deviation across all tracks for each cycle
medianNormalizedAmps = [];
stdNormalizedAmps = [];
numCycles = max(sum(cycleAmplitudes ~= 0, 2));  % Get the maximum number of cycles

% Loop through each cycle
for cycleIdx = 1:numCycles
    cycleAmps = [];  % Initialize an array to store the normalized amplitudes for the current cycle across all tracks
    
    for i = 1:numSignals
        % If the current signal has enough cycles
        if sum(cycleAmplitudes(i, :) ~= 0) >= cycleIdx
            cycleAmps = [cycleAmps; normalizedAmplitudes(i, cycleIdx)];
        end
    end
    
    % Calculate median and standard deviation for the current cycle across all tracks
    medianNormalizedAmps = [medianNormalizedAmps; median(cycleAmps,"omitmissing")];
    stdNormalizedAmps = [stdNormalizedAmps; std(cycleAmps,"omitmissing")];
end

% Plot normalized amplitude with error bars (standard deviation) vs cycle number
figure;
errorbar(1:numCycles, medianNormalizedAmps, stdNormalizedAmps, '-o', 'LineWidth', 1.5);
xlabel('Cycle Number');
ylabel('Median Normalized Amplitude');
title('Median Normalized Amplitude vs Cycle Number with Error Bars');
grid on;
legend('Median Normalized Amplitude');

% ** New functionality for ERK values plot (figure 5)**
% Plotting the 5th graph (Median ERK values vs Cycle number with Error Bars)
figure;
errorbar(1:size(median_ERK_val_at_Amp, 1), median_ERK_val_at_Amp(:, 1), median_ERK_val_at_Amp(:, 2), '-o', 'LineWidth', 1.5);
xlabel('Cycle Number');
ylabel('Median ERK Value');
title('Median ERK Value vs Cycle Number with Error Bars');
grid on;
legend('Median ERK Value');

% Display the plot
disp('Median ERK Value vs Cycle Number with Error Bars plotting complete.');

% Concatenate median and std into a new matrix
median_Clock_NormalizedAmps= [medianNormalizedAmps, stdNormalizedAmps];  % Concatenate horizontally

% Transpose the Amp_timepoints matrix
Amp_timepoints_transposed = Amp_timepoints';

% Assume Amp_timepoints is already defined

% Count the number of non-zero elements in each column
n_num = sum(Amp_timepoints_transposed' ~= 0, 1);  % Sum along rows (across columns), counting non-zero elements

n_num=nonzeros(n_num');
% median_Clock_NormalizedAmps = [median_Clock_NormalizedAmps,n_num];