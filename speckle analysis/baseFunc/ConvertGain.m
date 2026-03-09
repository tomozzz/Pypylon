function  [G, G0, g0] = ConvertGain(gain_dB,bitDepth,satCapacity)
%% function convertGain(gain,bBits,well)
%% Converts from dB to actual gain
% Input :
%     gain_dB     - scalar/vector of analog gain in dB (additional to the base gain G0 )
%     bitDepth    - detector bit depth
%     satCapacity - Saturation capacity [in electrons]
% Output :
%       G  - total Gain [DU/e] ( conversion from [e] to [DU] )
%       G0 - base Gain [DU/e] - the actual gain without camera additional analog gain, i.e. when gain_dB=0 
%       g0 - base gain [dB] - the actual gain without camera additional analog gain, i.e. when gain_dB=0 


G0 = 2^bitDepth/satCapacity;
G = 10.^(gain_dB./20) * G0;

g0 = 20*log10(G0);

