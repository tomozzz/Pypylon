% convert numerical array (arr) into cell array with strings
function ret = num2cellstr(arr)
    ret = cellfun(@(x) num2str(x), num2cell(arr),'Uniformoutput',false);