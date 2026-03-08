function finfo = GetParamsFromFileName(recName)
    % get rawName
    [~ , filename, ext] = fileparts(recName);
    if ~ismember(ext,{'.mat','.tiff','tif','.avi'})
        rawName = [filename, ext];
    else
        rawName = filename;
    end
    
    % get params one by one
    words = strsplit(rawName,'_');
    last_valid_param_name= '';
    stringSepChar = '^';
    for i = 1:numel(words)
        [param_name, param_val, param_units] = findNumberSubstrings(words{i});
        if isempty(param_name) % starts with numbers
            if i==numel(words) % if last parameter
                param_name = 'Ind'; % index
                finfo.(param_name) = param_val;
                finfo.units.(param_name) = param_units;
                continue;
            elseif ~isempty(last_valid_param_name) && ( ischar(finfo.(last_valid_param_name)) || isempty(finfo.(last_valid_param_name)) )
                finfo.(last_valid_param_name) = [finfo.(last_valid_param_name) '_' num2str(param_val) param_units ];
                finfo.units.(last_valid_param_name) = [ finfo.units.(last_valid_param_name) param_units ];
                continue;
            else 
                warning(['wrong record name format : ' , rawName]); 
                continue;
            end
        elseif ~isvarname( param_name ) && ~ismember(param_name,{'try','for','if','catch'}) % -> is not valid param_name for being a field name -> put together with previous 
            if nnz(param_name == stringSepChar)==1 
                words2 = strsplit(words{i});
                param_name = words2{1};
                param_val  = words2{2};
                param_units = '';
                clear words2
            else   
                error('Filename should contain valid parameter names (start with letters, no special characters');
            end
        else 
            last_valid_param_name = param_name;
        end
        finfo.(param_name) = param_val;
        finfo.units.(param_name) = param_units;
    end        

function [beforeNumber, number, afterNumber] = findNumberSubstrings(str)
    % Use regular expression to find the first number substring
    numberPattern = '[\+\-]?\d+(\.\d+)?';
    numberMatch = regexp(str, numberPattern, 'match', 'once');
    
    if isempty(numberMatch)
        % If no number substring is found, return empty strings
        beforeNumber = str;
        numberStr = '';
        afterNumber = '';
    else
        % Find the indices of the number substring
        numberIdx = strfind(str, numberMatch);
        
        % Extract the substrings before and after the number
        beforeNumber = str(1:numberIdx(1)-1);
        afterNumber = str(numberIdx(1)+length(numberMatch):end);
        
        % Extract the first number substring found
        numberStr = numberMatch;
    end
    
    if ~isnan(str2double(numberStr)) % value is numeric
        number = str2double(numberStr);
    else
        number = numberStr;
    end
        
