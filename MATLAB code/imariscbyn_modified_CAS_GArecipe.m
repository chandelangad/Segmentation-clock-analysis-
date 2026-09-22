clear all;
[file, path] = uigetfile('*.xlsx', 'Select an Excel file');
if isequal(file, 0)
    disp('No file selected. Exiting.');
    return;
end
cd(path);
% Create a folder named 'ERK images'
folderName = 'ERK images';
mkdir(folderName);

% Get the full path of the newly created folder
folderPath = fullfile(pwd, folderName);
cd(folderPath);

% Load the selected Excel file
data = xlsread(fullfile(path, file));
data(:,13) = [1:1:length(data(:,1))];
cytoid = data(:,13);
cytoframe = data(:,2);
cytoint = data(:,11);
nucint = data(:,5);
nucid = data(:,13);
nucframe = cytoframe;
posx= data(:,7);
posy =data(:,8);
posz= data(:,9);

L=length(cytoid);
frs=max(cytoframe);
cytomat=[ones(L,1),cytoint,cytoid,cytoframe];
nucmat=[zeros(L,1),nucint,nucid,nucframe];
posmat=[abs(posx),abs(posy),abs(posz),cytoframe];
sorter=[cytomat;nucmat];
CbyN=zeros(1,5);
maxC1=0;
minx=30000;
miny=30000;
maxx=0;
maxy=0;
for fr=1:frs
framat=sorter(sorter(:,4)==fr,:);
posfmat=posmat(posmat(:,4)==fr,:);
[sortfr,isort]=sort(framat(:,3));
s=1;
while s<length(framat)
    if sortfr(s)==sortfr(s+1)&&framat(isort(s),1)==1
        new=[framat(isort(s),2)/framat(isort(s+1),2),posfmat(isort(s),:)]; 
       % maxC1=max(maxC1,new(1));
        maxy=max(maxy,new(3));
        maxx=max(maxx,new(2));
        miny=min(miny,new(3));
        minx=min(minx,new(2));
        %CbyN{fr,1}=[CbyN{fr};new];
        CbyN=[CbyN;new];
        %CbyN{fr,2}=[CbyN{fr},framat(isort(s),2)/framat(isort(s+1),2)];
        s=s+2;
    else
        s=s+1;
    end
end
end


% % scatter dots
% % m = prctile(CbyN(:,1),0.5);
% % maxC1=prctile(CbyN(:,1),99.5);
% % frs=max(CbyN(:,5));
% % for fr=1:frs   
% %     figure
% % cnf=CbyN{fr};
% % cnf=CbyN(CbyN(:,5)==fr,1:4);
% % [scn,icn]=sort(cnf(:,1));
% % 
% % for i=1:length(cnf)
% %     scatter(cnf(icn(i),2),cnf(icn(i),3),300,'MarkerEdgeColor',[min(max((scn(i)-m),0)/(maxC1-m),1),0,0],'MarkerFaceColor',[min(max((scn(i)-m),0)/(maxC1-m),1),0,0]);
% %     set(gca,'nextplot','add');
% % end
% % set(gca,'Color','k')
% % axis off
% % axis equal, axis([minx maxx miny maxy])
% % end
% % 
% % for fr=1:frs
% %     fig = get(groot,'CurrentFigure');
% %     fig.Color='k';
% %     fig.WindowState='maximized';
% %     set(fig,'InvertHardCopy','Off');
% %     saveas(fig,strcat('frameERK_', num2str(fig.Number),'.tif'));
% %     close
% % end

%%voronoi
frs=max(CbyN(:,5));
m = prctile(CbyN(:,1),3);
maxC1=prctile(CbyN(:,1),97);
csvwrite('0.5_perctle.csv',m);
csvwrite('99.5_perctle.csv',maxC1);


for fr=1:frs
    figure
%cnf=CbyN{fr};
cnf=CbyN(CbyN(:,5)==fr,1:4);
[scn,icn]=sort(cnf(:,1));
posxy=[];

for i=1:length(cnf)
    posxy=[posxy;cnf(icn(i),2),cnf(icn(i),3)];
end

[r,f]=voronoin(posxy);

for i = 1:length(f)
    fill(r(f{i},1),r(f{i},2),[min(max((scn(i)-m),0)/(maxC1-m),1),0,0]) ;
    set(gca,'nextplot','add');
end
set(gca,'Color','k')
%bord=convhull(posxy);
bord=boundary(posxy);
plot(posxy(bord,1),posxy(bord,2),'-g');

%axis off
axis equal, axis([minx maxx miny maxy])
end


for fr=1:frs
    fig = get(groot,'CurrentFigure');
    fig.Color='k';
    fig.WindowState='maximized';
    set(fig,'InvertHardCopy','Off');
    saveas(fig,strcat('vorframeERK_', num2str(fig.Number),'.tif'));
    close
end

minx= minx/0.3;
maxx=maxx/0.3;
miny=miny/0.3;
maxy=maxy/0.3;
x_frame=maxx-minx;
y_frame=maxy-miny;
 csvwrite('minx.csv',minx);
 csvwrite('miny.csv',miny);
 csvwrite('x_frame.csv',x_frame);
 csvwrite('y_frame.csv',y_frame);
