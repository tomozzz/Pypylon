%% [ recordsOut, paramOut ] = SortRecords(recordsIn, paramName)
% Sort Records names by specific parameter value
% Input:
%   recordsIn  - cell array with records names
%   paramName  - parameter name by which record should be sorted
% Output: 
%   recordsOut - sorted cell array with records names
%   parameter  - sorted array of parameters values

function [ recordsOut, paramOut ] = SortRecords(recordsIn, paramName)
    paramVec = nan(numel(recordsIn),1);    
    for rec_i = 1:numel(recordsIn)
        sp = strsplit(recordsIn{rec_i},filesep); foldername = sp{end};
        paramVec(rec_i) = ExtractParametersFromString(foldername,paramName);
    end
    
    [ paramOut , sortInd ] = sort(paramVec);
    recordsOut = recordsIn(sortInd);

