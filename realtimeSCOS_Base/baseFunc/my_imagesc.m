function [fig , hImage ]= my_imagesc(im,mask,ax)
% [fig , hImage ]= my_imagesc(im,mask,ax)
% Create figure with stretched image between 0.99 and 0.01 percentiles and equal axis

im = double(im);
if nargin < 3
    fig = figure('Units','Normalized','Position',[0.05,0.05,0.6,0.8]); 
    hImage = imagesc(im); 
    ax = gca;
else
    hImage = imagesc(ax,im);
    fig = [];
end

if nargin < 2
    mask = true(size(im));
end

Lims = prctile(im(mask),[1, 99]);
if isequal(Lims(1),Lims(2))
    meanLims = mean(Lims);
    Lims = meanLims + 0.5*[-1 1];
end

SetAxisEqual(ax);
set(ax,'CLim',Lims); 
colorbar;
colormap gray;

function SetAxisEqual(ax)
if nargin < 1
    ax = gca();
end
axis(ax,'equal'); 
dataObj = findall(ax,'Type','Image');
set(ax,'XLim', dataObj.XData + 0.5*[-1 1], 'YLim', dataObj.YData + 0.5*[-1 1])