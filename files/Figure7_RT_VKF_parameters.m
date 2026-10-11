%% REACTION TIME, LEARNING RATE AND VOLATILITY UPDATE RATE
%
% PURPOSE: Compare two groups under two controllability conditions and three
% predictability levels. Source SCR headings have been corrected to log RT.
% REQUIREMENTS: MATLAB R2020b+; Statistics and Machine Learning Toolbox.
% MATLAB execution has not been verified against participant data.
%
% INPUTS: Four behavioral Excel workbooks, one per group/condition, with
% one worksheet per participant. Sheet names identify participants. A Block
% header is preferred; otherwise BLOCK_COLUMN is used. RT values must be ms.
% RT_COLUMNS defaults to [5 4] for groups A/B. Missing/nonnumeric values and
% RT outside inclusive 100-800 ms are omitted BEFORE natural-log transform.
% Predictability summaries are trial-weighted means of log RT across selected
% blocks. Overall mean log RT uses ALL retained trials in the worksheet.
% A mean of logged trials is not the log of the mean raw reaction time.
%
% STATISTICS: Separate 2 x 2 x 3 mixed repeated-measures ANOVAs for log RT and
% learning rate, including between-group tests and within-group interactions.
% Lambda: paired condition tests within each group plus equal-variance group
% tests within each condition; Bonferroni family of four.
%
% OUTPUTS: PNG/vector PDF figures, Excel statistics, extracted CSV, matching
% and inclusion tables, and MAT objects. 
% Author: Daniyal, University of Melbourne.



clear; clc; close all;
rng(1,'twister');

%% CONFIGURATION
inputDir = fullfile(pwd,'rt_vkf_inputs');
outdir = fullfile(pwd,'rt_vkf_outputs');
GROUP_LABELS = ["Group A","Group B"];
CONDITION_LABELS = ["Controllable","Uncontrollable"];
PRED_LABELS = ["HP","MP","UP"];
behaviorFiles = ["group_a_behavior_s1.xlsx","group_a_behavior_s2.xlsx"; ...
                 "group_b_behavior_s1.xlsx","group_b_behavior_s2.xlsx"];
parameterFiles = ["group_a_parameters_s1.xlsx","group_a_parameters_s2.xlsx"; ...
                  "group_b_parameters_s1.xlsx","group_b_parameters_s2.xlsx"];
BLOCK_COLUMN = 2;
RT_COLUMNS = [5 4]; % Trial-level RT columns for groups A/B.
RT_MIN = 100; % Inclusive lower limit, milliseconds.
RT_MAX = 800; % Inclusive upper limit, milliseconds.
BLOCK_SETS = {["Block1","Block5","Block8","Block10"], ...
              ["Block3","Block4","Block7","Block9"],["Block2","Block6"]};
SUBJECT_COLUMN = "Subject";
LR_COLUMNS = ["LR_HP","LR_MP","LR_UP"];
LAMBDA_COLUMN = "Lambda";
PARAMETER_SHEET = 1;
APPLY_3SD = true;
SD_THRESHOLD = 3;
RUN_LME = true;
png_dpi = 600;
colors = zeros(2,3,2);
colors(:,:,1) = [0.05 0.18 0.60;0.55 0.05 0.05];
colors(:,:,2) = [0.55 0.80 0.98;0.98 0.82 0.82];
assert(isfinite(SD_THRESHOLD) && SD_THRESHOLD>0,'Invalid SD threshold.');
assert(RT_MIN>0 && RT_MAX>RT_MIN && isfinite(RT_MAX),'Invalid RT bounds.');
if ~isfolder(outdir)
    [ok,msg] = mkdir(outdir);
    if ~ok, error('Cannot create output directory: %s',msg); end
end

%% READ AND MATCH FOUR SOURCES WITHIN EACH GROUP
G = cell(2,1); matching = table(); audit = table(); extracted = table();
for g = 1:2
    B = cell(2,1); P = cell(2,1);
    for c = 1:2
        B{c} = local_read_behavior(fullfile(inputDir,behaviorFiles(g,c)), ...
            BLOCK_COLUMN,RT_COLUMNS(g),BLOCK_SETS,RT_MIN,RT_MAX);
        P{c} = local_read_parameters(fullfile(inputDir,parameterFiles(g,c)), ...
            PARAMETER_SHEET,SUBJECT_COLUMN,LR_COLUMNS,LAMBDA_COLUMN);
    end
    ids = intersect(B{1}.id,B{2}.id,'stable');
    ids = intersect(ids,P{1}.id,'stable'); ids = intersect(ids,P{2}.id,'stable');
    if numel(ids)<2, error('Fewer than two matched participants in %s.',GROUP_LABELS(g)); end
    matching = [matching;table(GROUP_LABELS(g),numel(B{1}.id),numel(B{2}.id), ...
        numel(P{1}.id),numel(P{2}.id),numel(ids),'VariableNames', ...
        {'Group','Behavior_S1','Behavior_S2','Parameters_S1','Parameters_S2','Matched'})];
    A = nan(numel(ids),6); L=A; lambda=nan(numel(ids),2); overall=lambda;
    for c = 1:2
        [~,ib]=ismember(ids,B{c}.id); [~,ip]=ismember(ids,P{c}.id);
        columns=(c-1)*3+(1:3);
        A(:,columns)=B{c}.logRT(ib,:); L(:,columns)=P{c}.lr(ip,:);
        overall(:,c)=B{c}.overall(ib); lambda(:,c)=P{c}.lambda(ip);
    end
    rawA=A; rawL=L;
    for c = 1:2
        for p = 1:3
            k=(c-1)*3+p; pair=[L(:,k),A(:,k)];
            finite=all(isfinite(pair),2); outlier=false(numel(ids),1);
            if APPLY_3SD
                indices=find(finite);
                outlier(indices)=local_sd_outliers(pair(finite,:),SD_THRESHOLD);
            end
            keep=finite & ~outlier;
            L(~keep,k)=NaN; A(~keep,k)=NaN;
            audit=[audit;table(repmat(GROUP_LABELS(g),numel(ids),1),ids, ...
                repmat(CONDITION_LABELS(c),numel(ids),1),repmat(PRED_LABELS(p),numel(ids),1), ...
                finite,outlier,keep,'VariableNames', ...
                {'Group','Subject','Condition','Predictability','Finite_pair','Outlier_excluded','Retained_pair'})];
        end
    end
    G{g}=struct('id',ids,'logRT',A,'lr',L,'lambda',lambda,'overall',overall, ...
        'rawLogRT',rawA,'rawLR',rawL);
    variables={'LogRT_HP_S1','LogRT_MP_S1','LogRT_UP_S1','LogRT_HP_S2','LogRT_MP_S2','LogRT_UP_S2', ...
        'LR_HP_S1','LR_MP_S1','LR_UP_S1','LR_HP_S2','LR_MP_S2','LR_UP_S2', ...
        'Lambda_S1','Lambda_S2','OverallLogRT_S1','OverallLogRT_S2'};
    extracted=[extracted;table(repmat(GROUP_LABELS(g),numel(ids),1),ids, ...
        'VariableNames',{'Group','Subject'}),array2table([A,L,lambda,overall],'VariableNames',variables)];
end
statsFile=fullfile(outdir,'RT_VKF_Statistics.xlsx');
writetable(extracted,fullfile(outdir,'RT_VKF_Extracted.csv'));
writetable(extracted,statsFile,'Sheet','Extracted_data');
writetable(matching,statsFile,'Sheet','Matching');
writetable(audit,statsFile,'Sheet','Paired_cleaning');

%% SEPARATE MIXED ANOVAS
anovaModels=cell(2,1); outcomes=["logRT","lr"]; outcomeLabels=["LogRT","LearningRate"];
responses={'HP_S1','MP_S1','UP_S1','HP_S2','MP_S2','UP_S2'};
within=table(categorical(repelem(CONDITION_LABELS(:),3)), ...
    categorical(repmat(PRED_LABELS(:),2,1)), 'VariableNames',{'Condition','Predictability'});
for o = 1:2
    wide=table(); inclusion=table();
    for g = 1:2
        Y=G{g}.(char(outcomes(o))); keep=all(isfinite(Y),2);
        if sum(keep)<2, error('Too few complete cases for %s, %s.',outcomeLabels(o),GROUP_LABELS(g)); end
        ids=G{g}.id; subject="G"+g+"_"+ids(keep);
        wide=[wide;table(subject,categorical(repmat(GROUP_LABELS(g),sum(keep),1)), ...
            'VariableNames',{'Subject','Group'}),array2table(Y(keep,:),'VariableNames',responses)];
        inclusion=[inclusion;table(repmat(GROUP_LABELS(g),numel(ids),1),ids,keep, ...
            'VariableNames',{'Group','Subject','Complete_case'})];
    end
    rm=fitrm(wide,'HP_S1-UP_S2 ~ Group','WithinDesign',within); anovaModels{o}=rm;
    writetable(local_export_table(ranova(rm,'WithinModel','Condition*Predictability')), ...
        statsFile,'Sheet',char(outcomeLabels(o)+"_within"));
    writetable(local_export_table(anova(rm)),statsFile,'Sheet',char(outcomeLabels(o)+"_between"));
    writetable(inclusion,statsFile,'Sheet',char(outcomeLabels(o)+"_inclusion"));
end

%% LAMBDA T-TESTS: FOUR-TEST BONFERRONI FAMILY
lambdaTests=table(strings(4,1),nan(4,1),nan(4,1),nan(4,1),zeros(4,1),zeros(4,1), ...
    'VariableNames',{'Comparison','t','df','p_raw','N1','N2'});
for g = 1:2
    x=G{g}.lambda(:,1); y=G{g}.lambda(:,2); keep=isfinite(x)&isfinite(y);
    x=x(keep); y=y(keep); t=NaN; df=NaN; p=NaN;
    if numel(x)>=2, [~,p,~,st]=ttest(x,y); t=st.tstat; df=st.df; end
    lambdaTests(g,:)={GROUP_LABELS(g)+": S1 vs S2",t,df,p,numel(x),numel(y)};
end
for c = 1:2
    x=G{1}.lambda(:,c); y=G{2}.lambda(:,c); x=x(isfinite(x)); y=y(isfinite(y));
    t=NaN; df=NaN; p=NaN;
    if numel(x)>=2 && numel(y)>=2
        [~,p,~,st]=ttest2(x,y,'Vartype','equal'); t=st.tstat; df=st.df;
    end
    lambdaTests(c+2,:)={"Group A vs Group B: "+CONDITION_LABELS(c),t,df,p,numel(x),numel(y)};
end
lambdaTests.p_bonf=min(lambdaTests.p_raw*4,1);
lambdaTests.Significant_raw=lambdaTests.p_raw<0.05;
lambdaTests.Significant_bonf=lambdaTests.p_bonf<0.05;
writetable(lambdaTests,statsFile,'Sheet','Lambda_ttests');

%% CORRELATIONS WITH SOURCE BONFERRONI FAMILIES
corrTable=table();
for family = 1:3
    labels=["LR_vs_LogRT","Lambda_vs_OverallLogRT","Lambda_vs_LogRT"];
    count=3; factor=12;
    if family==2, count=1; factor=4; end
    for c = 1:2
        for g = 1:2
            for p = 1:count
                k=(c-1)*3+p;
                if family==1, x=G{g}.lr(:,k); y=G{g}.logRT(:,k); pred=PRED_LABELS(p);
                elseif family==2, x=G{g}.lambda(:,c); y=G{g}.overall(:,c); pred="Overall";
                else, x=G{g}.lambda(:,c); y=G{g}.logRT(:,k); pred=PRED_LABELS(p); end
                st=local_corr_stats(x,y);
                corrTable=[corrTable;table(labels(family),GROUP_LABELS(g),CONDITION_LABELS(c),pred, ...
                    st.N,st.r,st.p,min(st.p*factor,1),'VariableNames', ...
                    {'Analysis','Group','Condition','Predictability','N','r','p_raw','p_bonf'})];
            end
        end
    end
end
corrTable.Significant_raw=corrTable.p_raw<0.05;
corrTable.Significant_bonf=corrTable.p_bonf<0.05;
writetable(corrTable,statsFile,'Sheet','Correlations');
%% SUMMARY FIGURES
for metric = 1:2
    if metric==1, label="Learning rate"; field="lr";
    else, label="Mean log RT (ln ms)"; field="logRT"; end
    fig=figure('Color','w','Position',[100 100 1500 600]); tl=tiledlayout(1,3);
    for p = 1:3
        ax=nexttile(tl); hold(ax,'on'); handles=gobjects(4,1); legends=strings(4,1);
        for c = 1:2
            for g = 1:2
                k=(c-1)*2+g; y=G{g}.(char(field))(:,(c-1)*3+p);
                y=y(isfinite(y));
                boxchart(ax,k*ones(size(y)),y,'BoxFaceColor',[0.68 0.68 0.68], ...
                    'BoxFaceAlpha',0.3,'MarkerStyle','none');
                handles(k)=scatter(ax,k+(rand(numel(y),1)-0.5)*0.2,y,36,colors(g,:,c), ...
                    'filled','MarkerEdgeColor','k');
                legends(k)=GROUP_LABELS(g)+" ("+CONDITION_LABELS(c)+")";
            end
        end
        ax.XTick=[1.5 3.5]; ax.XTickLabel=cellstr(CONDITION_LABELS);
        title(ax,PRED_LABELS(p)); ylabel(ax,label); ax.Box='off';
        if p==3
            lgd=legend(ax,handles,cellstr(legends),'Orientation','horizontal','Box','off');
            lgd.Layout.Tile='north';
        end
    end
    local_save_figure(fig,outdir,char(field+"_GroupComparison"),png_dpi);
end
fig=figure('Color','w'); ax=axes(fig); hold(ax,'on'); handles=gobjects(4,1); legends=strings(4,1);
for c = 1:2
    for g = 1:2
        k=(c-1)*2+g; y=G{g}.lambda(:,c); y=y(isfinite(y));
        boxchart(ax,k*ones(size(y)),y,'BoxFaceColor',[0.68 0.68 0.68],'MarkerStyle','none');
        handles(k)=scatter(ax,k+(rand(numel(y),1)-0.5)*0.2,y,36,colors(g,:,c),'filled');
        legends(k)=GROUP_LABELS(g)+" ("+CONDITION_LABELS(c)+")";
    end
end
ax.XTick=[1.5 3.5]; ax.XTickLabel=cellstr(CONDITION_LABELS); ylabel(ax,'Volatility update rate');
legend(ax,handles,cellstr(legends),'Location','eastoutside');
local_save_figure(fig,outdir,'Lambda_GroupComparison',png_dpi);

%% CORRELATION FIGURES: LR AND LAMBDA WITH LOGRT
for family = 1:3
    for c = 1:2
        panels=3;
        if family==2, panels=1; end
        fig=figure('Color','w','Position',[100 100 1400 550]); tl=tiledlayout(1,panels);
        for p = 1:panels
            ax=nexttile(tl); hold(ax,'on'); handles=gobjects(2,1);
            for g = 1:2
                if family==1
                    x=G{g}.lr(:,(c-1)*3+p); y=G{g}.logRT(:,(c-1)*3+p); xlabelText="Learning rate";
                elseif family==2
                    x=G{g}.lambda(:,c); y=G{g}.overall(:,c); xlabelText="Volatility update rate";
                else
                    x=G{g}.lambda(:,c); y=G{g}.logRT(:,(c-1)*3+p); xlabelText="Volatility update rate";
                end
                keep=isfinite(x)&isfinite(y); x=x(keep); y=y(keep);
                handles(g)=scatter(ax,x,y,36,colors(g,:,c),'filled','MarkerEdgeColor','k');
                st=local_corr_stats(x,y); factor=12;
                if family==2, factor=4; end
                annotation=sprintf('%s: r = %.2f, p_raw = %.2g, p_Bonf = %.2g, N = %d', ...
                    GROUP_LABELS(g),st.r,st.p,min(st.p*factor,1),st.N);
                text(ax,0.02,0.98-(g-1)*0.08,annotation,'Units','normalized', ...
                    'VerticalAlignment','top','Color',colors(g,:,c),'FontSize',10, ...
                    'Interpreter','none');
                if numel(x)>=2 && std(x)>0
                    coeff=polyfit(x,y,1); xx=linspace(min(x),max(x),100);
                    plot(ax,xx,polyval(coeff,xx),'Color',colors(g,:,c),'HandleVisibility','off');
                end
            end
            xlabel(ax,xlabelText); ylabel(ax,'Mean log RT (ln ms)');
            if family==2, title(ax,"Overall | "+CONDITION_LABELS(c));
            else, title(ax,PRED_LABELS(p)+" | "+CONDITION_LABELS(c)); end
            if p==panels, legend(ax,handles,cellstr(GROUP_LABELS),'Location','eastoutside'); end
        end
        local_save_figure(fig,outdir,sprintf('Correlation_family%d_condition%d',family,c),png_dpi);
    end
end

%% OPTIONAL LOGRT LME AND EXPLORATORY SUBSET FITS
lmeModels=cell(5,1); longTable=table();
if RUN_LME
    for g = 1:2
        for c = 1:2
            for p = 1:3
                y=G{g}.logRT(:,(c-1)*3+p); lambda=G{g}.lambda(:,c);
                n=numel(y); ids="G"+g+"_"+G{g}.id;
                longTable=[longTable;table(y,lambda,categorical(repmat(PRED_LABELS(p),n,1)), ...
                    categorical(repmat(CONDITION_LABELS(c),n,1)), ...
                    categorical(repmat(GROUP_LABELS(g),n,1)),categorical(ids), ...
                    'VariableNames',{'LogRT','Lambda','Predictability','Condition','Group','Subject'})];
            end
        end
    end
    longTable=longTable(isfinite(longTable.LogRT)&isfinite(longTable.Lambda),:);
    lmeModels{1}=fitlme(longTable,'LogRT ~ Lambda*Predictability*Condition*Group + (1|Subject)');
    writetable(local_as_table(anova(lmeModels{1})),statsFile,'Sheet','LME_full');
    for g = 1:2
        part=longTable(string(longTable.Group)==GROUP_LABELS(g),:);
        part.Group=removecats(part.Group);
        lmeModels{g+1}=fitlme(part,'LogRT ~ Lambda*Predictability*Condition + (1|Subject)');
        writetable(local_as_table(anova(lmeModels{g+1})),statsFile,'Sheet',sprintf('LME_group%d',g));
    end
    for c = 1:2
        part=longTable(string(longTable.Condition)==CONDITION_LABELS(c),:);
        part.Condition=removecats(part.Condition);
        lmeModels{c+3}=fitlme(part,'LogRT ~ Lambda*Predictability*Group + (1|Subject)');
        writetable(local_as_table(anova(lmeModels{c+3})),statsFile,'Sheet',sprintf('LME_condition%d',c));
    end
    writetable(longTable,statsFile,'Sheet','LME_data');
end
save(fullfile(outdir,'RT_VKF_AllOutputs.mat'),'G','extracted','matching','audit', ...
    'anovaModels','lambdaTests','corrTable','lmeModels','longTable', ...
    'behaviorFiles','parameterFiles','BLOCK_SETS','RT_COLUMNS','BLOCK_COLUMN', ...
    'APPLY_3SD','SD_THRESHOLD','RT_MIN','RT_MAX','RUN_LME');
fprintf('Completed. Statistics: %s\n',statsFile);

%% HELPERS
function S=local_read_behavior(file,blockCol,rtCol,blockSets,rtMin,rtMax)
    if ~isfile(file), error('Missing behavior file: %s',file); end
    sheets=string(sheetnames(file)); ids=local_ids(sheets,file);
    logRT=nan(numel(ids),3); overall=nan(numel(ids),1);
    for i = 1:numel(ids)
        T=readtable(file,'Sheet',sheets(i),'VariableNamingRule','preserve');
        if width(T)<max(blockCol,rtCol), error('Insufficient columns in %s, %s.',file,sheets(i)); end
        names=string(T.Properties.VariableNames); named=find(strcmpi(names,'Block'),1);
        column=blockCol;
        if ~isempty(named), column=named; end
        blocks=strtrim(string(T{:,column})); raw=T{:,rtCol};
        if isnumeric(raw)
            values=double(raw);
        else
            values=str2double(strtrim(string(raw)));
        end
        values=values(:);
        values(~isfinite(values)|values<rtMin|values>rtMax)=NaN;
        values=log(values); % Filter before natural-log transform.
        for p = 1:3
            logRT(i,p)=mean(values(ismember(blocks,blockSets{p})),'omitnan');
        end
        overall(i)=mean(values,'omitnan');
    end
    S=struct('id',ids(:),'logRT',logRT,'overall',overall);
end
function S=local_read_parameters(file,sheet,subjectColumn,lrColumns,lambdaColumn)
    if ~isfile(file), error('Missing parameter table: %s',file); end
    T=readtable(file,'Sheet',sheet,'VariableNamingRule','preserve');
    required=[subjectColumn,lrColumns,lambdaColumn];
    if ~all(ismember(required,string(T.Properties.VariableNames)))
        error('Parameter table %s requires: %s',file,strjoin(required,', '));
    end
    ids=local_ids(string(T.(char(subjectColumn))),file); values=nan(height(T),4);
    columns=[lrColumns,lambdaColumn];
    for k = 1:4
        raw=T.(char(columns(k)));
        if isnumeric(raw), x=double(raw);
        else
            text=strtrim(string(raw)); x=str2double(text);
            bad=~ismissing(text)&text~=""&lower(text)~="nan"&isnan(x);
            if any(bad), error('Nonnumeric parameter in %s.',file); end
        end
        x(~isfinite(x))=NaN; values(:,k)=x(:);
    end
    S=struct('id',ids(:),'lr',values(:,1:3),'lambda',values(:,4));
end
function ids=local_ids(ids,file)
    ids=regexprep(upper(strtrim(ids)),'_S[12]$','');
    if any(ismissing(ids)|ids=="")||numel(unique(ids))~=numel(ids)
        error('Empty or duplicate normalized participant IDs in %s.',file);
    end
end
function flagged=local_sd_outliers(Y,threshold)
    flagged=false(size(Y,1),1);
    for k = 1:size(Y,2)
        x=Y(:,k); finite=isfinite(x);
        if sum(finite)<2, continue; end
        mu=mean(x(finite)); sd=std(x(finite));
        if sd>0, flagged=flagged|(finite&abs(x-mu)>threshold*sd); end
    end
end
function st=local_corr_stats(x,y)
    keep=isfinite(x)&isfinite(y); x=x(keep); y=y(keep);
    st=struct('N',numel(x),'r',NaN,'p',NaN);
    if numel(x)>=3 && std(x)>0 && std(y)>0
        [st.r,st.p]=corr(x,y,'Type','Pearson');
    end
end
function T=local_export_table(T)
    names=string(T.Properties.RowNames);
    if isempty(names)
        if ismember('Between',T.Properties.VariableNames), names=string(T.Between);
        else, names=strings(height(T),1); end
    end
    T=addvars(T,names,'Before',1,'NewVariableNames','Effect');
    T.Properties.RowNames={};
end
function T=local_as_table(T)
    if ~istable(T), T=dataset2table(T); end
end
function local_save_figure(fig,outdir,name,dpi)
    exportgraphics(fig,fullfile(outdir,[name,'.png']),'Resolution',dpi);
    exportgraphics(fig,fullfile(outdir,[name,'.pdf']),'ContentType','vector');
end
