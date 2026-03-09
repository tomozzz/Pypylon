
%% function [fullName, recName] = GenerateFileName(folder,camParams,setupParams,prefix,suffix,saveFormat,forceWrite,src)
function [fullName, recName] = GenerateFileName(folder,camParams,setupParams,prefix,suffix,saveFormat,forceWrite,src)
    mustFieldsForFilename = {'Gain','ExposureTime'};
    for field = mustFieldsForFilename(:)'
        if ~isfield(camParams,field{1})
            camParams.(field{1})= src.(field{1});
        end
    end
    camParamsStr   = Struct2String(camParams,CamParamsLUT());
    setupParamsStr = Struct2String(setupParams,SetupParamsLUT);
        
    recNameBase = sprintf('%s%s%s%s',prefix,setupParamsStr,camParamsStr,suffix);
    if isempty(recNameBase)
        error('Record name cannot be empty! Please specify prefix/suffix or enable parameters in the name');
    end
    if isempty(prefix) && recNameBase(1)=='_'
        recNameBase(1) = []; 
    end

    if forceWrite
        if exist([folder '\' recNameBase '.avi'],'file')
            delete([folder '\' recNameBase '.avi']);
        elseif exist([folder '\' recNameBase ],'file')                
            delete([folder '\' recNameBase ]);
        end
        recName = recNameBase;
    else
        pattern = [regexptranslate('escape', recNameBase), '_(\d+)(.avi)?$'];

        samefiles = dir([folder '\' recNameBase '_*']);
        if ~isempty(samefiles)
            samefiles = samefiles([samefiles.isdir] | cellfun(@(x) endsWith(x,',avi'), {samefiles.name} ,'UniformOutput',true)); % filter only folders and .avi files
            samefiles = { samefiles(cellfun(@(x) ~isempty(regexp(x, pattern,'once')), {samefiles.name} ,'UniformOutput',true)).name } ; % find files with the same name but different index
            filesIndices = [];
            for filename=samefiles(:)'
                match = regexp(filename{1}, pattern,'tokens');
                filesIndices = [ filesIndices, str2double(match{1}{1}) ]; %#ok<AGROW>
            end
            if isempty(filesIndices)
                newIndex = 0;
            else
                newIndex = max(filesIndices)+1;
            end
            if newIndex > 999
                error(['Too many records with the same name "' folder '\' recNameBase '"' ] );
            end
        else
            newIndex = 0;
        end
        newIndexStr = sprintf('%0*d',3,newIndex);
        recName = [recNameBase '_' newIndexStr];
    end
    if ismember(saveFormat,{'avi'})
        recName = [recName '.avi']; 
    end
    fullName = fullfile(folder,recName);
end

function  [lut, name_out , units ] = CamParamsLUT(name_in)
    % Create lut
    lut = { 'ExposureTime'          , 'expT'   , 'us' ;...
            'AcquisitionFrameRate'  , 'FR'     , 'Hz' ;...
            'BlackLevel'            , 'BL'     , 'DU' ;...
            'Gain'                  , 'Gain'   , 'dB' ;...
          };
    
    % Check lut first column uniqueness 
    if  numel(unique(lut(:,1))) ~= size(lut,1)
        error('Values in first column of CamParamsLut should be unique!')
    end
    
    % Extract param from lut  
    if nargin > 0
        ind = ismember(lut(:,1),name_in);
        if numel(ind) == 0
            name_out = name_in;
        elseif numel(ind) > 1
            error('Two identical entries in lut table');
        else
            name_out = lut(ind,2);
            units    = lut(ind,3);
        end
    else
        name_out = '';
        units = '';
    end
end

function  [lut, name_out, units ] = SetupParamsLUT(name_in)
    % Create lut
    lut = { 'Lens'                  , 'Lens'   , 'mm' ;...
            };
    
    % Check lut first column uniqueness 
    if  numel(unique(lut(:,1))) ~= size(lut,1)
        error('Values in first column of CamParamsLut should be unique!')
    end
    
    % Extract param from lut  
    if nargin > 0
        ind = ismember(lut(:,1),name_in);
        if numel(ind) == 0
            name_out = name_in;
        elseif numel(ind) > 1
            error('Two identical entries in lut table');
        else
            name_out = lut(ind,2);
            units    = lut(ind,3);
        end
    else
        name_out = '';
        units = '';
    end
end


