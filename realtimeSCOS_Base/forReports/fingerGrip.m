fig = figure('Units','Normalized','Position',[0,0.05, 0.7, 0.8]);

records = strcat('C:\Users\viti_\Documents\MATLAB\SCOS\Records\Japan\OneChannel\1000micronFiber\', ...
    {'Mikie_Hand\t1_SDS2.5cm_handGrip_FR10Hz_expT15ms_Gain10dB'...
     'Rin_Hand\t1_handGrip_FR10Hz_expT15ms_Gain20dB'...
     'Kairi_Hand\t1_SDS2.5cm_handGrip_FR10Hz_expT15ms_Gain20dB'...
     'Yukina_Hand\t1_SDS2.5cm_handGrip_FR10Hz_expT15ms_Gain15dB'...
     'Ryoga_Hand\t1_FingerGrip_FR10Hz_expT15ms_Gain20dB'...     
    });

% records = strcat('C:\Users\viti_\Documents\MATLAB\SCOS\Records\Japan\OneChannel\1000micronFiber\', ...
%     {'KairiHead\nBacklTask_SDS3cmCap_Power300mW_FR5Hz_expT20ms_Gain36dB'...
%      'YukinaHead\nBackTask_P400mW_expT20ms_Gain24dB_FR3.75Hz_SDScmcm_RightCap_sourse10_Detector9'...
%      'RyogaHead\nBackTask_P400mW_expT20ms_Gain36dB_FR3.75Hz_SDScmcm_RightCap_forehead'...  
%      'SayakaHead\nBackTask_P400mW_expT20ms_Gain24dB_Mono12p_FR3.75Hz_SDS3cm_LeftCap_forehead_try2'...
%     });

% records = strcat('C:\Users\viti_\Documents\MATLAB\SCOS\Records\Japan\OneChannel\1000micronFiber\', ...
%     {'KairiHead\nBacklTask_SDS3cmCap_Power300mW_FR5Hz_expT20ms_Gain36dB'...
%      'YukinaHead\nBackTask_P400mW_expT20ms_Gain24dB_FR3.75Hz_SDScmcm_RightCap_sourse10_Detector9'...
%      'RyogaHead\nBackTask_P400mW_expT20ms_Gain36dB_FR3.75Hz_SDScmcm_RightCap_forehead'...  
%      'SayakaHead\nBackTask_P400mW_expT20ms_Gain24dB_Mono12p_FR3.75Hz_SDS3cm_LeftCap_forehead_try2'...
%     });

avgWindowSeconds = 0;
for i = 1:numel(records)
    [fig1,fig2]  = Calc_Averaged_rBFI(records{i},avgWindowSeconds);
end


h = actxserver('PowerPoint.Application');
h.Presentation.invoke;
Presentation = h.Presentation.Add;
blankSlide = Presentation.SlideMaster.CustomLayouts.Item(7);

% fi1=figure(1);
% 
% fi1.Position=[1,41,1280,700];
% 
% newslide = Presentation.Slides.AddSlide(4*(ssub-1)+1,blankSlide); 
% print(fi1,'-dmeta');
% 
% Image1 = newslide.Shapes.Paste;
% set(Image1, 'Left', 0);
% set(Image1, 'Top', 40);
% 
% tmp = newslide.Shapes.AddTextbox('msoTextOrientationHorizontal',0,0,400,70);
% tmp.TextFrame.TextRange.Text = [char(conditionname(ssub,:)),'-1cm'];
% 
% Presentation.SaveAs([pwd,'\Laser-IPSandPD-SPADAQ4C_20240319.pptx']);
% h.Quit;

% % % import mlreportgen.ppt.*
% % % % openExample('rptgen/CreateAPresentationWithDefaultFormattingExample')
% % % 
% % % ppt = Presentation('myFirstPresentation.pptx');
% % % open(ppt);
% % % 
% % % slide1 = add(ppt,'Title Slide');
% % % replace(slide1,'Title','Modeling the US Population');
% % % replace(slide1,'Subtitle','A Risky Business');
% % % slide2 = add(ppt,'Title and Content');
% % % replace(slide2,'Title','Population Modeling Approach');
% % % replace(slide2,'Content',{ ...
% % %     'Fit polynomial to U.S. Census data' ...
% % %     'Use polynomials to extrapolate population growth' ...
% % %     ['Based on "Computer Methods for Mathematical Computations",'...
% % %    ' by Forsythe, Malcolm and Moler, published by Prentice-Hall in 1977'] ...
% % %     'Varying polynomial degree shows riskiness of approach'});
% % % 
% % % slide3 = add(ppt,'Title and Content');
% % % replace(slide3,'Title','Slide3');
% % % img1 = 'plot1.png';
% % % saveas(fig1,img1);
% % % images = [images {img1}];
% % % replace(slide3,'Content',Picture(img1));
% % % 
% % % titleSlide = add(ppt,'Title Slide');
% % % textSlide  = add(ppt,'Title and Content');
% % % 
% % % paraObj = Paragraph('My First Presentation');
% % % paraObj.FontColor = 'red';
% % % replace(titleSlide,'Title',paraObj);
% % % replace(textSlide,'Content',{'Subject A','Subject B','Subject C'});
% % % 
% % % 
% % % close(ppt);
% % % rptview(ppt);
% % % % h.delete;
% % % % 
