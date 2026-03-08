%%  records = ChooseRecords(recordsFolder, filter, sortBy, isFile)
% Choose records with specific filter.
% if sortBy string is present the records are ordered by this parameter, and paramArr is set to values of this parameter
% isFile - [optional] weather the record is a file (.avi or .mat file) or a folder ( presumably containing one .avi or many .tiff files ) 
function [records, paramArr] = ChooseRecords(recordsFolder, filter, sortBy, isFile )

    renames = dir([recordsFolder filesep filter]); 
    if exist('isFile','var') && ~isempty(isFile) 
        if isFile
            if ~ismember(isFile,[0,1])
                error('Wrong 3-d parameter ''isFile'': must be 0 or 1');
            end
            renames([renames.isdir]) = [];
        else
            renames(~[renames.isdir]) = [];
        end
    end
    renames = {renames.name}';
    renames(ismember(renames,{'.','..'})) = [];
    renames( cellfun(@(x) endsWith(x,'.mat'),renames) ) = []; % remove _info.mat files from the records list
    renames( cellfun(@(x) endsWith(x,'.json'),renames) ) = [];
    
    records = fullfile(recordsFolder,renames);
    
    if exist('sortBy','var') && ~isempty(sortBy) 
        [ records, paramArr] = SortRecords(records,sortBy);
    else
        paramArr = [];
    end
        
