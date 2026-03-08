% [ speckleSize ] = FindSpeckleSize(Im, thresholod)
% Find Speckle mean diameter , via finding when autocorrection of the image 
% equals 'thresholod'
% Input:
%  Im        - 2D image
%  threshold - in range of 1-0 , threshold for autocorrelation for speckle definition [optional, defaul=0.367]
%  center    - center [x,y] of the circle of interest [optional , but must be together with 'radius' input variable]
%  radius    - radius of the circle of interest [optional , but must be together with 'center' input variable] 
%        If center and radius are present, the calculation is performed on a squere that fits into the circle
function [ speckleSize ] = FindSpeckleSize(Im, threshold , center, radius)
    if exist('center','var') && ~isempty(center)
        if ~exist('radius','var') || isempty(radius)
            error(' ''center'' variable should come with ''radius'' variable input');
        end
        half_edge = round( radius / sqrt(2) ) ; % squere edge that fits inside a circle
        center = round(center);
        Im = Im( center(2) + (-half_edge:half_edge) , center(1) + (-half_edge:half_edge)  );
%         figure; imagesc(Im)
    end
    
    if ~exist('threshold','var') || isempty(threshold)
        threshold = 0.367;
    end

    [ ~ , Acorr ]  = Autocorrelation2D(Im);
%      figure; imagesc(Acorr)
    
     indx = find(Acorr(1,:) < threshold ,1 ) - 1 ; % find the pixel index that is 
     indy = find(Acorr(:,1) < threshold ,1 ) - 1 ;
     
     half_sizeX = indx + 1/diff(Acorr(1,indx:indx+1))*( threshold - Acorr(1,indx)) - 1; % interpolation
     half_sizeY = indy + 1/diff(Acorr(indy:indy+1),1)*( threshold - Acorr(indy,1)) - 1; % interpolation
     speckleSize = 2*mean([half_sizeX,half_sizeY]) ; 
end