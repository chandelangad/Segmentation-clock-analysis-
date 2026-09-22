clear;

[file, path] = uigetfile('*.xlsx', 'Select an Excel file');
if isequal(file, 0)
    disp('No file selected. Exiting.');
    return;
end

% Get file name without extension
[~, name, ~] = fileparts(file);

% Create folder name: "ExcelFileName-ERK images"
folderName = [name '-ERK images'];

% Full folder path
fullFolderPath = fullfile(path, folderName);

% Create folder only if it does not exist
if ~exist(fullFolderPath, 'dir')
    mkdir(fullFolderPath);
end


cd(fullFolderPath);

% Load the selected Excel file
data = xlsread(fullfile(path, file));
m =length(data(:,1));
data(:,10) = [1:1:m];
data(:,11)= ones(m,1);
cytoid = data(:,10);
cytoframe = data(:,11);
cytoint = data(:,8);
nucint = data(:,2);
nucid = data(:,10);
nucframe = cytoframe;
posx= data(:,4);
posy =data(:,5);
posz= data(:,6);

L=length(cytoid);
frs=max(cytoframe);
cytomat=[ones(L,1),cytoint,cytoid,cytoframe];
nucmat=[zeros(L,1),nucint,nucid,nucframe];
posmat=[abs(posx),abs(posy),abs(posz),cytoframe];
sorter=[cytomat;nucmat];
CbyN=zeros(1,5);
maxC1=0;
minx=10000;
miny=10000;
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

%%here go to split movie concatenate.m if you have data in multiple pieces of frame intervals 
%{


%%delaunaySFC5 voronoi no edge effect

m = prctile(CbyN(:,1),5);
maxC1=prctile(CbyN(:,1),95);
frs=max(CbyN(:,5));

for fr=1:frs   
    figure
cnf=CbyN(CbyN(:,5)==fr,1:4);
[scn,icn]=sort(cnf(:,1));
posxy=[];
for i=1:length(cnf)
    posxy=[posxy;cnf(icn(i),2),cnf(icn(i),3)];
end

TR = delaunayTriangulation(posxy);

T = TR.ConnectivityList;
TR2 = triangulation(T,posxy(:,1),posxy(:,2));
F = featureEdges(TR2,pi)';
G=sort(unique(reshape(F,1,prod(size(F)))),'descend');
posxy(G,:)=[];
TR = delaunayTriangulation(posxy);
T = TR.ConnectivityList;
colorn=zeros(length(posxy),1);
%countern=colorn;

for tr=1:size(TR,1)
    N = neighbors(TR,tr);
    N=N(~isnan(N));
    
    neigh=zeros(1,length(N));
    for nn=1:length(N)
        neigh(nn)=mean(min(max((scn(T(N(nn),:))-m),0)/(maxC1-m),1))-0.3 ;
    end
    cellf=mean(min(max((scn(T(tr,:))-m),0)/(maxC1-m),1))-0.3;
    sfc=max(0,min(max(neigh)/cellf-1,2))/2;
    
    for itr=1:3
    colorn(T(tr,itr))=max(colorn(T(tr,itr)),sfc/2);
    end
end
%colorn=colorn./countern;
ICc=[posxy,colorn];
[scc,icc]=sort(ICc(:,3));
[r,f]=voronoin(posxy);
for i = 1:length(f)
    fill(r(f{icc(i)},1),r(f{icc(i)},2),[scc(i),0,0]) ;
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
    saveas(fig,strcat('delaframeSFC_', num2str(fig.Number),'.tif'));
    close
end

%}

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

%% voronoi 
frs = max(CbyN(:,5));
m = prctile(CbyN(:,1),1);
maxC1 = prctile(CbyN(:,1),99);

for fr = 1:frs
    figure
    cnf = CbyN(CbyN(:,5) == fr, 1:4);
    [scn, icn] = sort(cnf(:,1));
    posxy = [];
    
    for i = 1:length(cnf)
        posxy = [posxy; cnf(icn(i),2), cnf(icn(i),3)];
    end
    
    % Flip posxy vertically
    % max_y = max(posxy(:,2));
    % posxy(:,2) = max_y - posxy(:,2);
    
    [r, f] = voronoin(posxy);
    
    for i = 1:length(f)
        fill(r(f{i},1), r(f{i},2), [min(max((scn(i)-m),0)/(maxC1-m),1), 0, 0]);
        set(gca,'nextplot','add');
    end
    
    set(gca, 'Color', 'k');
    bord = boundary(posxy);
    plot(posxy(bord,1), posxy(bord,2), '-g');
    
    axis equal, axis([minx maxx miny maxy]);
end

for fr=1:frs
    fig = get(groot,'CurrentFigure');
    fig.Color='k';
    fig.WindowState='maximized';
    set(fig,'InvertHardCopy','Off');
    saveas(fig, strcat(name, '-vorframeERK_', num2str(fig.Number), '.tif'));
    close
end

minx= minx/0.3;
maxx=maxx/0.3;
miny=miny/0.3;
maxy=maxy/0.3;
x_frame=maxx-minx;
y_frame=maxy-miny;

% Define the filename for the CSV file
filename = [name '-output_data.csv'];

% Create headers as a cell array
headers = {'0.5 Percentile', '99.5 Percentile', 'Min X', 'Min Y', 'X Frame', 'Y Frame'};

% Combine headers and data into one cell array for writing to CSV
data = [m(:), maxC1(:), minx(:), miny(:), x_frame(:), y_frame(:)]; % Concatenate data into columns
outputData = [headers; num2cell(data)];  % Combine headers with data

% Write to CSV file
writecell(outputData, filename);

