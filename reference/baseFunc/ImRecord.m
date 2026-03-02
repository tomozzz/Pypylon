function [im, fig, info] = ImRecord(recordName)
%%
%   imagesc the first frame of the record
%   [im, fig ,info] = ImRecord(recordName)
%
%
if nargin == 0
    [recordName] = uigetdir();
    if numel(dir([recordName '.avi'])) > 1
        [filename, filepath] = uigetfile([recordName '\*.avi']);
        recordName = fullfile(filepath,filename);
    end
end

[ im , info] = ReadRecord(recordName,1); %, {'Tint','FR','Gain','Fiber'});

[~, rawName, ext]  = fileparts(recordName);
if exist(recordName,'file') == 7
    rawName = [rawName ext]; % in case there is a dot in file name ext wont be empty
end    
rawName = strrep(rawName,'_',' ');

fig = figure(); 
imagesc(im); colormap gray; colorbar
axis equal % axis equal should be before setting the limits
ax = gca();
ax.XLim = [ 0 size(im,2) ];
ax.YLim = [ 0 size(im,1) ];
title(rawName,'interpreter','none')
