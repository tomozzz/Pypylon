% Converts PTW raw video files (from WiDy software) to batches of tiff
% files sequentially numbered. 

% Andrew Wade
% awade@ligo.caltech.edu
% September 2017

% Adapted from example code given on p10 of WiDy SWIR User Manual 


function rec = PTWtoTIFF(file,convertToTiffFlag)
    if nargin < 1
        % Open a Dialogbox to get the database file .ptw
        [filename, pathname] = uigetfile('*.ptw', 'Choose a picture ptw file');
        file = fullfile(pathname,filename);
        convertToTiffFlag = 1;
    end
    % Initialization of the file pointer.
    fid = fopen(file,'r');
    [pathname,filename] = fileparts(file);
    pathname = [pathname filesep];
    
    % File Header length in Bytes.
    LgthFileMainHeader = 3476;
    % Image Header length in Bytes.
    LgthImHeader = 1016;
    % Recover the number of pixels in images:
    fseek(fid, 23, 'bof');
    NbPixelImage = fread(fid,1,'uint32');
    % Recover the total number of images:
    fseek(fid, 27, 'bof');
    Nbimage = fread(fid,1,'uint32');
    % Recover width of images:
    fseek(fid, 377, 'bof');
    NbColImage = fread(fid,1,'uint16');
    % Recover height of images:
    fseek(fid, 379, 'bof');
    NbRowImage = fread(fid,1,'uint16');
    % Set the pointer at the beginning of the image header.
    fseek(fid, LgthFileMainHeader, 'bof');
    % Initialization of a viedo buffer.
    rec = zeros(NbRowImage,NbColImage,Nbimage,'uint16');
    h = waitbar(0,[strrep(filename,'\','\\') ' database importation : ' num2str(0) '/' num2str(Nbimage) ]);
    % Main Loop
    for i=1:Nbimage 
        waitbar(i/Nbimage,h,[filename ' database importation : ' num2str(i) '/' num2str(Nbimage) ]); % The file pointer fid is incremented by LgthImHeader.
        fread(fid,LgthImHeader); % The image is extracted from the file.
        B = fread( fid , [NbColImage,NbRowImage] , 'uint16' ); % The image is stored in raw order in the binary file.
        rec(:,:,i) = uint16( B' ); % The image is stored in the buffer.
    end
    close(h)
    fclose('all');


    % Now the write out routieen
    if convertToTiffFlag
        h2 = waitbar(0,[filename ' export to tiff : ' num2str(0) '/' num2str(Nbimage) ]);
        tiffFolderName = fullfile( pathname, [filename '_InGaAsNIT']);
        mkdir(tiffFolderName);
        for ii=1:Nbimage
            waitbar(ii/Nbimage,h2,[filename ' database importation : ' num2str(ii) '/' num2str(Nbimage) ]); % The file pointer fid is incremented by LgthImHeader.
            writeoutBuff = rec(:,:,ii);
            if ii==1
                my_imagesc(writeoutBuff);
            end
            imwrite(writeoutBuff,[tiffFolderName,'\frame_',num2str(ii),'.tiff'])
        end
        close(h2)
        fclose('all');
    end
end