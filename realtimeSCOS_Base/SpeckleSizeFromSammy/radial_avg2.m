function [Int, XX]=radial_avg2(Frm, Cnt,limitfactor)
%  Radial average with respect to the point of coordinates Cnt - center by Marco Leonetti. 06/23/2021
%  takes  frame, finds the pixelwise distance from the pixel of coordinates
%  Cnt(1) Cnt(2). Then finds the Intensity at each distance and average
%  contribution form the pixels at the same distance with proper normalization.

%  See also  https://mlphotonics.wordpress.com/

% Frm : Frame (2d matrix) to be evaluated
% Cnt : Coordinates of the center location [Cnt(1) Cnt(2)] on which to calculate the radial average
% [Int XX] : Profile of the Intensity (Int) of the versus ther radial coordinte (Int); "plot(XX,Int)" to visaulize it



[row, col]=size(Frm); %% find size of the input frame
%% Generating meshgrid
XXX_V=1:col;
YYY_V=1:row;
[XXX ,YYY]=meshgrid(XXX_V,YYY_V);

%% Centering Meshgrid
XXX=XXX-Cnt(2);
YYY=YYY-Cnt(1);

%% Pixelwise Distance from the center
Dist=sqrt(XXX.^2+YYY.^2);
% Getting all the unique distances for this grid
Dist_V=unique(reshape(Dist,1,[]));

%% Optional Limiting of Dist_V
Dist_V=Dist_V(1:round(limitfactor*length(Dist_V)));

%% renaming
Int = zeros(size(Dist_V));
L=numel(Dist_V);
progressStep = max(1, floor(L / 10));

for ddd=1:L
    if mod(ddd, progressStep) == 0 || ddd == L
        fprintf('ACF calc progress: %d %%\n', round(100*ddd/L));
    end
    Distance=Dist_V(ddd); %%given a distance
    TMP1=Dist==Distance; %% find pixels with that distance, logical map of grid.
    TMP2=Frm.*TMP1; %% find intensity at these locations, 
    Int(ddd)=sum(sum(TMP2))/sum(sum(TMP1)); %% Finding intensity and normalixing by number of pixles at the right distance

end

XX=Dist_V;
