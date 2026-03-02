function [center, radius] = AutoFindSpot(im)
relativeIforCircle = 0.3;

% Find center of mass
x = 1 : size(im, 2); % Columns.
y = 1 : size(im, 1); % Rows.
[X, Y] = meshgrid(x, y);
meanIm = mean(im(:));
centerOfMassX = mean(im(:) .* X(:)) / meanIm;
centerOfMassY = mean(im(:) .* Y(:)) / meanIm;
% figure; imshowpair(CreateCircleMask(size(im),5,centerOfMassY,centerOfMassX),im)

% Find MaxI
maxI = mean(im(CreateCircleMask(size(im),5,centerOfMassY,centerOfMassX)));

% Find Expected Radius
numOfPixelsInSpot = nnz(im(:) > maxI*relativeIforCircle);
approxRadius = sqrt(numOfPixelsInSpot/pi());

[center, radius] = imfindcircles(im(:) > maxI*relativeIforCircle,round(approxRadius*[0.9 1.1]),'ObjectPolarity','bright','Sensitivity',0.99);

if numel(radius) > 1
    warning('more that one raius was found!')
    
    [radius, maxIdx] = max(radius);
    center = center(maxIdx,:);
end

