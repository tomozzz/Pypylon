<<<<<<< Updated upstream
function [ masks, totMask, channels, fig , h_circles, h_txt] = autoFindRIOMultichannel(im,approxRadius,expectedNumOfChannels)
 
 if ~exist('approxRadius','var')
     approxRadius = 200; 
%      radiumLimits = [0.8 1.05];
%      Sensitivity = 0.997;
 end
 
 %% find circles
 %first look in large range of raduuses8
 expectedNumOfChannels = 1;
[centers, radii, metric] = imfindcircles(im ,round(approxRadius*[0.8 1.2]),'ObjectPolarity','bright','Sensitivity',0.997); %,'EdgeThreshold',0.3);
% smearedIm = medfilt2(im,[13 13]);
% smearedIm = filter2(ones(25),im);
% my_imagesc(smearedIm)
=======
function [ masks, totMask, channels, fig , h_circles, h_txt] = autoFindRIOMultichannel(im,approxRadius)
>>>>>>> Stashed changes

if numel(radii) > expectedNumOfChannels*1.5
    % try less sensitive
    [~,max_idx] = max(metric);
    [centers, radii, metric] = imfindcircles(im ,round(radii(max_idx)*[0.95 1.02]),'ObjectPolarity','bright','Sensitivity',0.996); %,'EdgeThreshold',0.3);
    %my_imagesc(im); viscircles(centers, radii,'Color','b','EnhanceVisibility',false,'LineWidth',1);
elseif numel(radii) < expectedNumOfChannels
    % try to find other channels too - try more sensitive
    
end
% [centers1, radii1, metric1] = ReduceDuplicates(centers1, radii1, metric1,approxRadius);
% [~,max_idx] = max(metric1);
% [centers, radii, metric] = imfindcircles(im ,round(radii1(max_idx)*[0.95 1.05]),'ObjectPolarity','bright','Sensitivity',0.996); %,'EdgeThreshold',0.3);
% [centers, radii, metric] = ReduceDuplicates(centers, radii, metric,approxRadius);

<<<<<<< Updated upstream
 % my_imagesc(im); viscircles(centersBright, radiiBright,'Color','b','EnhanceVisibility',false,'LineWidth',1);
=======
%% find circles
[centers1, radii1, metric1] = imfindcircles(im ,round(approxRadius*[0.85 1.05]),'ObjectPolarity','bright','Sensitivity',0.996); %,'EdgeThreshold',0.3);
[centers1, radii1, metric1] = ReduceDuplicates(centers1, radii1, metric1,approxRadius);
[~,max_idx] = max(metric1);
[centers, radii, metric] = imfindcircles(im ,round(approxRadius*[0.95 1.05]),'ObjectPolarity','bright','Sensitivity',0.996); %,'EdgeThreshold',0.3);
[centers, radii, metric] = ReduceDuplicates(centers, radii, metric,approxRadius);

% my_imagesc(im); viscircles(centersBright, radiiBright,'Color','b','EnhanceVisibility',false,'LineWidth',1);
>>>>>>> Stashed changes
radiusMargins = 9;
channels.Radii = radii-radiusMargins;
channels.Centers = centers;
channels.Metric = metric;

%% Plot
fig = my_imagesc(im); 
fig.Units = 'Normalized';
fig.Position = [0.1 0.2 0.5 0.6];

h_circles = viscircles(channels.Centers, channels.Radii,'Color','y','EnhanceVisibility',false,'LineWidth',1);

h_txt = [];
for i=1:numel(channels.Radii)
    h_txt(i) = text(channels.Centers(i,1),channels.Centers(i,2),num2str(i),'FontSize',14,'Color','y');     %#ok<AGROW>
end
%% Create masks
masks = cell(1,numel(channels.Radii) );
[x,y] = meshgrid(1:size(im,2),1:size(im,1));

totMask = false(size(im,1),size(im,2)); 
for k = 1:numel(channels.Radii)    
    masks{k} = false(size(im,1),size(im,2));
    masks{k}((x-channels.Centers(k,1)).^2 + (y-channels.Centers(k,2)).^2 < channels.Radii(k)^2 ) = true;
    totMask = totMask |  masks{k};
end
<<<<<<< Updated upstream
 
function [Centers,Radii,Metric] = ReduceDuplicates(orig_centers,orig_radii,orig_metric,approxRadius)
N = numel(orig_radii);
 distances = nan(N);
 checked_rows = [];

Centers = nan([0 2]);
Radii = [];
Metric = [];
 for i = 1:N    
     if ismember(i,checked_rows)
         continue;
     end
     same_circle_rows = i;
     for j = 1:N
         if j==i; continue; end
        distances(i,j) = norm(diff(orig_centers([i,j],:)));
         if distances(i,j) < approxRadius
            same_circle_rows = [same_circle_rows j]; %#ok<AGROW>
         end
     end 
     checked_rows = [ checked_rows , same_circle_rows ];
 
    [~, max_ind] =  max( orig_metric(same_circle_rows) ) ; 
     max_row = same_circle_rows(max_ind);

    Centers(end+1,:) = orig_centers(max_row,:);
    Radii(end+1)   = orig_radii(max_row);
    Metric(end+1)  = orig_metric(max_row);
 end

