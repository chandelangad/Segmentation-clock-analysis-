% Ask user to select the Excel or CSV file
[fileName, filePath] = uigetfile({'*.xlsx;*.xls;*.csv'}, 'Select the data file');
if isequal(fileName, 0)
    disp('No file selected. Exiting.');
    return;
end

fullPath = fullfile(filePath, fileName);

% Read the data
data = readcell(fullPath);  % works for both Excel and CSV

% Extract columns, skipping header
originalNames = data(2:end, 1);
randomNumbers = data(2:end, 2);
shuffledNumbers = data(2:end, 3);

% Convert random numbers and shuffled numbers to strings
if isnumeric(randomNumbers{1})
    randomNumbersStr = cellfun(@num2str, num2cell(cell2mat(randomNumbers)), 'UniformOutput', false);
else
    randomNumbersStr = randomNumbers;
end

if isnumeric(shuffledNumbers{1})
    shuffledNumbersStr = cellfun(@num2str, num2cell(cell2mat(shuffledNumbers)), 'UniformOutput', false);
else
    shuffledNumbersStr = shuffledNumbers;
end

% Create map: random number → original name
map = containers.Map(randomNumbersStr, originalNames);

% Match shuffled numbers to original names
matchedNames = cell(size(shuffledNumbersStr));
for i = 1:length(shuffledNumbersStr)
    key = shuffledNumbersStr{i};
    if isKey(map, key)
        matchedNames{i} = map(key);
    else
        matchedNames{i} = 'NOT FOUND';
    end
end

% Create logbook: full mapping as a cell array
logbook = [...
    {'Original Name', 'Random Number', 'Shuffled Number', 'Matched Original Name'}; ...
    [originalNames, randomNumbersStr, shuffledNumbersStr, matchedNames] ...
];

disp('✅ Matching complete. Variable "logbook" created in workspace.');
