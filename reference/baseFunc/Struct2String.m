%% totStr = Struct2String(paramS,lut) 
% Convert struct to a string consisting of combination of param names,values and units, separated by underscores between params
% Input: 
%   paramS - parameters struct. one of the fields can be addToFilename. If it's value is false -> empty string is returned.
%            it also can be a struct, so for every field that has false value, it won't be added to the name
%   lut - lookup table , converting from camera parameters long names to filename short names, and units
%         Should be 3 columns cell array , where first column is camera/setup param name, second is file param name, and third is the units
% Output:
%   totStr - string for filename consisting of pairs of param names and values and units, separated by underscores
%
function totStr = Struct2String(paramS,lut)
    if ~exist('lut','var'); lut = []; end
    if ~isfield(paramS,'addToFilename')
        addToFilenameFlag = true; % default is adding parameters to string
        addToFilenameStruct = [];
    else
        if isstruct(paramS.addToFilename)
            addToFilenameFlag   =  true;
            addToFilenameStruct = paramS.addToFilename;
        else
            addToFilenameFlag = paramS.addToFilename;
            addToFilenameStruct = [];
        end
        paramS = rmfield(paramS,'addToFilename');
    end
    
    totStr = '';
    if addToFilenameFlag && ~isempty(paramS)            
        for pname_cell = fieldnames(paramS)'
            param_name = pname_cell{1};
            
            if ~isempty(addToFilenameStruct) && isfield(addToFilenameStruct,param_name) && ~addToFilenameStruct.(param_name)
                continue; % skip this parameter
            end
                            
            % get parameter value
            param_val = paramS.(param_name);
            
            % convert from numeric value to str if needed
            if isnumeric(param_val); param_val = num2str(param_val); end
            
            % rename if parameter appears in lut
            [param_str, param_units ] = FindInLut(lut,param_name);
            
            % replace units if user set them manually
            if isfield(paramS,'units') && isfield(paramS.units,param_name)
                param_units = paramS.units.(param_name);
            end
            % special case for ExposureTime
            if strcmp(param_name,'ExposureTime')                
                param_val = num2str(paramS.(param_name)/1000);
                param_units = 'ms';
            end
            
            % add current parameter to totStr
            totStr = [ totStr '_' param_str param_val param_units ]; %#ok<AGROW>            
        end         
    end
end     

function [ name_out, units ] = FindInLut(lut,name_in)
    units = '';
    if isempty(lut)
        name_out = name_in;
        return
    end

    if iscell(lut) && size(lut,2) == 3        
            ind = find(ismember(lut(:,1),name_in));
            if numel(ind) == 0
                name_out = name_in;
            elseif numel(ind) > 1 
                error('Two identical entries in lut table');
            else
                name_out = lut{ind,2};
                units    = lut{ind,3};
            end
    else
        error(['Wrong Lut format, must be a nx3 Cell Array,\n' ...
               'where firs column is name_in, second is name_out and third is the units']);
    end
end