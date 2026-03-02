% convert  cell array with strings into numerical array (arr) 
function ret = cellstr2num(cellArr)
    ret = cell2mat(cellfun(@(x) str2double(x), cellArr,'Uniformoutput',false));