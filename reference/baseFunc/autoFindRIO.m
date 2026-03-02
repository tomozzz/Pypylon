function [mask, circ] = autoFindRIO(im)

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
    relativeIforCircle = 0.3;
    numOfPixelsInSpot = nnz(im(:) > maxI*relativeIforCircle);
    approxRadius = sqrt(numOfPixelsInSpot/pi());
    
    [centers, radii] = imfindcircles(im > maxI*relativeIforCircle,round(approxRadius*[0.9 1.1]),'ObjectPolarity','bright','Sensitivity',0.99);
    if numel(radii) > 0
        [circ.Radius,max_ind] = max(radii);
        circ.Center = centers(:,max_ind);    
    else
        mask = [];
        circ.Center = Nan;
        circ.Radius = Nan;
    end
    if isfield(handles.fig_SCOS_GUI.UserData,'ROI')
        delete(handles.fig_SCOS_GUI.UserData.ROI.circ_handle);
    end

    mask = false(size(im,1),size(im,2));
    [x,y] = meshgrid(1:size(im,2),1:size(im,1));
    mask((x-circ.Center(1)).^2 + (y-circ.Center(2)).^2 < circ.Radius^2 ) = true;