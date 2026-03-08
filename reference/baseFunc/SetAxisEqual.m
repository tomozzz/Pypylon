function SetAxisEqual(ax)
if nargin < 1
    ax = gca();
end
axis equal; 
dataObj = findall(ax,'Type','Image');
set(ax,'XLim', dataObj.XData + 0.5*[-1 1], 'YLim', dataObj.YData + 0.5*[-1 1])
