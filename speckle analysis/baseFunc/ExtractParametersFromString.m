%----------------------------------------------------------
% Extract parameters values and units from a string (for example a filename) 
% The string format should be
% <paramName1><paramValue1><paramUnits1>_<paramName2><paramValue2><paramUnits2>_... etc
% Any other string is allowed in between .
% 
%----------------------------------------------------------
function [parameters_values, parameters_units] = ExtractParametersFromString(string,parameters_names)
    if ischar(parameters_names)
        parameters_names = {parameters_names};
    end
    
    if ischar(string)
        stringsArr = { string };
    else
        stringsArr = string;
    end
    % Initialize the output variables
    parameters_values = NaN(numel(stringsArr), numel(parameters_names));
    parameters_units = cell(numel(stringsArr), numel(parameters_names));
    
    % Extract the parameter values and units from the string
    for stringIdx = 1:numel(stringsArr)
        for i = 1:numel(parameters_names)
            % Generate a regular expression pattern for each parameter
            pattern = ['(?<=[/_\\]|^)' parameters_names{i} '(\d+(\.\d+)?)([a-zA-Z]*)'];

            % Use regular expression to match the pattern in the string
            matches = regexp(stringsArr{stringIdx}, pattern, 'tokens');

            if numel(matches) > 1
                error(['Error: Multiple occurrences of parameter "' parameters_names{i} '" found in the string.']);
            elseif ~isempty(matches)
                % Extract the value and unit from the matched tokens
                value = str2double(matches{1}{1});
                unit = matches{1}{2};

                % Store the extracted values and units in the output variables
                parameters_values(stringIdx,i) = value;
                parameters_units{stringIdx,i} = unit;
            else
                % Set empty string as units for the parameter not found
                parameters_units{stringIdx,i} = '';
            end
        end
    end

%     % Display the extracted parameter values and units
%     disp('Parameter Values:');
%     disp(parameters_values);
%     disp('Parameter Units:');
%     disp(parameters_units);