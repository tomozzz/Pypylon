%%  1. Spatial Test
% set seed
rng(2)

% set parameters
imSize = 100;
nOfBP = 140;
valLow = 70;
valHigh = 130;
valIm = 100;
varRange = 10;


synthetic_im = valIm*ones(imSize);
bp_ind = randperm(imSize^2,nOfBP-4-5*4-9-4); % 4 coners , 4 edges, 1 cross (9), , 1 square (4)

% corner pixels
bp_ind = [bp_ind , 1, imSize, (imSize*(imSize-1)+1) ,imSize*imSize]; 
% test upper and lower row 
bp_ind = [ bp_ind, sub2ind(imSize*[1 1], ones(1,5)          , [ round(imSize/4)+(1:2) round(imSize/2)+(1:3) ] ) ];
bp_ind = [ bp_ind  sub2ind(imSize*[1 1], ones(1,5)*imSize   , [ round(imSize/4)+(1:2) round(imSize/2)+(1:3) ] ) ];
% test right and left col
bp_ind = [ bp_ind, sub2ind(imSize*[1 1], [ round(imSize/4)+(1:2) round(imSize/2)+(1:3) ] , ones(1,5)        ) ];
bp_ind = [ bp_ind, sub2ind(imSize*[1 1], [ round(imSize/4)+(1:2) round(imSize/2)+(1:3) ] , ones(1,5)*imSize ) ];
% test clusters
% 1. cross
bp_ind = [ bp_ind, sub2ind(imSize*[1 1], round(imSize/2) + (-2:2)   ,  round(imSize/2)*ones([1 5])      ) ];
bp_ind = [ bp_ind, sub2ind(imSize*[1 1], round(imSize/2)*ones([1 4]),  round(imSize/2)+ [-2,-1,1,2]     ) ];  
% 2. small rectangle
bp_ind = [ bp_ind, sub2ind(imSize*[1 1], round(imSize/4) + [0 0 1 1], (round(imSize/2))+ [0 1 0 1] ) ];  

bp_err = randi(round(varRange/2)*[-1 1],size(bp_ind));
%%
low_bp_ind  = bp_ind(randperm(numel(bp_ind), nOfBP/2)) ;
high_bp_ind = bp_ind ( ~ismember( bp_ind , low_bp_ind ) );
synthetic_im(low_bp_ind)  =  valLow  + bp_err(1:numel(low_bp_ind));
synthetic_im(high_bp_ind) =  valHigh + bp_err(numel(low_bp_ind)+(1:numel(high_bp_ind)));

nnz(synthetic_im > valIm)
nnz(synthetic_im < valIm)

% % test clusters ( create cross in the middle:
% synthetic_im( round(imSize/2) + (-2:2:2) ,  round(imSize/2)  ) = valLow;
% synthetic_im( round(imSize/2) ,  round(imSize/2) + (-2:2:2)  ) = valLow;
% synthetic_im( round(imSize/2) + [-1 1]  ,  round(imSize/2) ) = valHigh;
% synthetic_im( round(imSize/2)   ,  round(imSize/2)  + [-1 1]) = valHigh;

expBPMap = (synthetic_im~=valIm);
my_imagesc(synthetic_im); 

%% test spatial bp 
[BPMap , spatialBP, temporalBP1 ]= FindBadPixels(synthetic_im);
figure; imshowpair(BPMap,expBPMap); title('Spatial Bad Pixels Maps: pink - expected, green - detected, white - both');   % my_imagesc(BPMap); title('Bad Pixels Map')
fixed_im = PixFix(synthetic_im,BPMap);  my_imagesc(BPMap); title('Synthetic Fixed Image')

my_imagesc(fixed_im); title('Fixed im');
% check 
assert(isequal(expBPMap,BPMap),'BP Not Equal!')
assert(all(fixed_im(:)==valIm),'Fixel image Not Right!')


%% 2. Add Temporal noise
nOfFrames = 30;
noiseBP = 30;
noiseRegular = 5;
synthetic_rec = valIm * ones([imSize,imSize,nOfFrames]);
% bad pixels: 
for k = bp_ind(:)'
    [y,x] = ind2sub(imSize*[1 1],k);
    synthetic_rec(y,x,:) = valIm + round( randn([1 nOfFrames]) * ( noiseBP + randn(1,1)*3 ) );
end

% good pixels:
not_bp = 1:imSize^2;
not_bp(bp_ind) = [];
for k = not_bp
    [y,x] = ind2sub(imSize*[1 1],k);
    synthetic_rec(y,x,:) = synthetic_im(y,x) + round( randn([1 nOfFrames]) * ( noiseRegular + randn(1,1) ) );
end

relTh = 4; 
tmpNoiseMat = std(synthetic_rec,0,3);
my_imagesc(tmpNoiseMat); title('temporal noise image');
figure; hist(tmpNoiseMat(:),200); title('temporal noise histogram')
hold on ; plot(median(tmpNoiseMat(:)) + relTh*std(tmpNoiseMat(:))*[1 1],get(gca,'YLim'),'--r');

bpMapTmpExp = false(imSize);
bpMapTmpExp(bp_ind) = true;

[BPMap , spatialBP, temporalBP1 ]= FindBadPixels(synthetic_rec,[],[],16,7);
figure; imshowpair(temporalBP1,bpMapTmpExp); title('Temporal Bad Pixels Maps: pink - expected, green - detected, white - both');
assert(isequal(temporalBP1,bpMapTmpExp),'Temporal BP 1 not equal');

[BPMap , spatialBP, temporalBP2 ]= FindBadPixels(synthetic_rec,[],relTh);
figure; imshowpair(temporalBP2,bpMapTmpExp); title('Temporal Bad Pixels Maps: pink - expected, green - detected, white - both');
assert(isequal(temporalBP2,bpMapTmpExp),'Temporal BP 2 not equal');

fixed_rec = PixFix(synthetic_rec,BPMap);
figure; imshowpair(synthetic_rec(:,:,5),fixed_rec(:,:,5),'montage','scaling','joint'); title('Original vs Fixed')
std(synthetic_rec(:,:,5))
% my_imagesc(fixed_rec(:,:,5)); title()
implay(fixed_rec)
%%
% I = imnoise(I,'salt & pepper');
%I = imnoise(I,'speckle',0.05) ;
% my_imagesc(I); title('With speckles');