%% QUESTIONNAIRE ASSOCIATIONS WITH ACCURACY AND VKF PARAMETERS
%
% Reuse for BAI, BDI, IUS total or either IUS factor. With the same input
% layouts, change only the filenames, QUESTIONNAIRE_NAME and LABEL below.
% Requires MATLAB R2020b+ and Statistics and Machine Learning Toolbox.
% MATLAB execution has not been verified against participant data.
%
%
% Behavioral Excel: one worksheet per participant, block column 2 by default;
% accuracy columns [12 8] for groups A/B. Accepts Correct/Incorrect, true/false
% and 1/0; unrecognized nonmissing values raise an error.
%
% VKF MAT: kgain_mat (participants x trials) and lambda_vec (one per participant).
% Optional subject_ids vector identifies rows. Without it, rows MUST follow
% the corresponding behavioral workbook sheet order. With it, rows are ID
% matched.
%
% ANALYSIS
% Optional single-pass +/-3 sample SD cleaning independently per variable and
% group: score, each accuracy/LR cell, and each condition's Lambda. Outliers
% become NaN.
% Questionnaire group comparison uses an unadjusted Welch independent t-test
% on the retained sample, after optional balancing. Difference is group A-B.
%
% Figures include r and raw/adjusted p-values.
% Author: Daniyal, University of Melbourne.


clear; clc; close all;

%% CHANGE THESE LABELS AND FILENAMES FOR EACH QUESTIONNAIRE
QUESTIONNAIRE_NAME  = 'IUS F2'; % Examples: 'BAI', 'BDI', 'IUS F1', 'IUS F2'.
QUESTIONNAIRE_LABEL = 'IUS F2 score';
base_dir = fullfile(pwd,'questionnaire_inputs');
output_root = fullfile(pwd,'questionnaire_outputs');

questionnaire_files = ["group_a_IUS_F2.xlsx","group_b_IUS_F2.xlsx"];
accuracy_files = ["group_a_behavior_s1.xlsx","group_a_behavior_s2.xlsx"; ...
                  "group_b_behavior_s1.xlsx","group_b_behavior_s2.xlsx"];
vkf_files = ["group_a_vkf_s1.mat","group_a_vkf_s2.mat"; ...
             "group_b_vkf_s1.mat","group_b_vkf_s2.mat"];

%% FIXED SETTINGS: KEEP THESE WHEN REUSING THE SAME DATA LAYOUT
GROUP_LABELS = ["Group A","Group B"]; % Set to your study group names.
CONDITION_LABELS = ["Controllable","Uncontrollable"];
PREDICTABILITY = ["HP","MP","UP"];
BLOCK_COL = 2;
ACC_COL = [12 8];
BLOCK_SETS = {["Block1","Block5","Block8","Block10"], ...
              ["Block3","Block4","Block7","Block9"],["Block2","Block6"]};
QUESTIONNAIRE_SHEET = 1;
QUESTIONNAIRE_SCORE_COLUMN = 1;
QUESTIONNAIRE_ID_COLUMN = 0; % 0: scores only, aligned to condition-1 sheets.
VKF_ID_FIELD = 'subject_ids'; % Optional MAT variable; otherwise sheet order.
APPLY_3SD = true;
SD_THRESHOLD = 3;
BALANCE_GROUPS = true;
BALANCE_METHOD = "closest_to_mean"; % Source rule; alternative: "random".
RANDOM_SEED = 1;
ALPHA = 0.05;
Y_LIMITS = {[0 100],[],[]}; % Accuracy, learning rate, Lambda.
PNG_DPI = 600;
colors = zeros(2,3,2);
colors(:,:,1) = [0.05 0.18 0.60;0.55 0.05 0.05];
colors(:,:,2) = [0.55 0.80 0.98;0.98 0.82 0.82];
rng(RANDOM_SEED,'twister');
assert(isfinite(SD_THRESHOLD)&&SD_THRESHOLD>0,'Invalid SD threshold.');
assert(ALPHA>0&&ALPHA<1,'Invalid alpha.');
assert(ismember(BALANCE_METHOD,["closest_to_mean","random"]),'Invalid balance method.');

safe_name = regexprep(strtrim(QUESTIONNAIRE_NAME),'[^A-Za-z0-9_-]+','_');
assert(~isempty(safe_name),'Questionnaire name cannot be empty.');
run_id = datestr(now,'yyyymmdd_HHMMSS');
outdir = fullfile(output_root,[safe_name,'_',run_id]);
if isfolder(outdir)
    [~,suffix]=fileparts(tempname);
    outdir=[outdir,'_',suffix];
end
figdir=fullfile(outdir,'Figures'); statsdir=fullfile(outdir,'Statistics');
datadir=fullfile(outdir,'Processed_Data');
folders={outdir,figdir,statsdir,datadir};
for k=1:numel(folders)
    [ok,msg]=mkdir(folders{k});
    if ~ok, error('Cannot create directory: %s',msg); end
end
stats_xlsx=fullfile(statsdir,[safe_name,'_Correlations.xlsx']);

%% READ, PAIR AND CLEAN WITHIN GROUP
G=cell(2,1); matching=table(); cleaning=table(); selection=table();
for g=1:2
    session=cell(2,1);
    for c=1:2
        session{c}=local_read_session(fullfile(base_dir,accuracy_files(g,c)), ...
            fullfile(base_dir,vkf_files(g,c)),BLOCK_COL,ACC_COL(g),BLOCK_SETS,VKF_ID_FIELD);
    end
    Q=local_read_questionnaire(fullfile(base_dir,questionnaire_files(g)), ...
        QUESTIONNAIRE_SHEET,QUESTIONNAIRE_SCORE_COLUMN,QUESTIONNAIRE_ID_COLUMN);
    if QUESTIONNAIRE_ID_COLUMN==0
        if numel(Q.score)~=numel(session{1}.id)
            error('%s: questionnaire has %d score rows; condition 1 has %d sheets. Add IDs or correct the row layout.', ...
                GROUP_LABELS(g),numel(Q.score),numel(session{1}.id));
        end
        Q.id=session{1}.id;
    end
    ids=intersect(session{1}.id,session{2}.id,'stable');
    ids=intersect(ids,Q.id,'stable');
    if isempty(ids), error('No matched participant IDs for %s.',GROUP_LABELS(g)); end
    [~,iq]=ismember(ids,Q.id); score=Q.score(iq);
    A=nan(numel(ids),6); L=A; lambda=nan(numel(ids),2);
    for c=1:2
        [~,ii]=ismember(ids,session{c}.id); columns=(c-1)*3+(1:3);
        A(:,columns)=session{c}.accuracy(ii,:);
        L(:,columns)=session{c}.lr(ii,:); lambda(:,c)=session{c}.lambda(ii);
    end
    raw=[score,A,L,lambda]; Y=raw;
    names=["QuestionnaireScore","Accuracy_HP_S1","Accuracy_MP_S1","Accuracy_UP_S1", ...
        "Accuracy_HP_S2","Accuracy_MP_S2","Accuracy_UP_S2", ...
        "LearningRate_HP_S1","LearningRate_MP_S1","LearningRate_UP_S1", ...
        "LearningRate_HP_S2","LearningRate_MP_S2","LearningRate_UP_S2","Lambda_S1","Lambda_S2"];
    for k=1:size(Y,2)
        x=Y(:,k); flagged=false(numel(x),1); lo=NaN; hi=NaN;
        if APPLY_3SD
            [x,flagged,lo,hi]=local_clean(x,SD_THRESHOLD);
        end
        Y(:,k)=x;
        cleaning=[cleaning;table(GROUP_LABELS(g),names(k),sum(isfinite(raw(:,k))), ...
            sum(flagged),lo,hi,'VariableNames',{'Group','Variable','N_finite','N_outliers','Lower','Upper'})];
    end
    eligible=isfinite(Y(:,1))&any(isfinite(Y(:,2:end)),2);
    G{g}=struct('id',ids,'names',names,'raw',raw,'cleaned',Y,'eligible',eligible,'keep',eligible);
    matching=[matching;table(GROUP_LABELS(g),numel(session{1}.id),numel(session{2}.id), ...
        numel(Q.score),numel(ids),sum(eligible),'VariableNames', ...
        {'Group','Sheets_S1','Sheets_S2','Questionnaire_rows','Matched','Eligible'})];
end

%% OPTIONAL BALANCING, RETAINING PARTICIPANT IDENTITY
if BALANCE_GROUPS
    target=min(sum(G{1}.eligible),sum(G{2}.eligible));
    for g=1:2
        eligible=find(G{g}.eligible); scores=G{g}.cleaned(eligible,1);
        if BALANCE_METHOD=="closest_to_mean"
            [~,order]=sort(abs(scores-mean(scores)),'ascend');
        else
            order=randperm(numel(eligible));
        end
        G{g}.keep=false(size(G{g}.eligible));
        G{g}.keep(eligible(order(1:target)))=true;
    end
end
for g=1:2
    S=G{g}; n=numel(S.id);
    selection=[selection;table(repmat(GROUP_LABELS(g),n,1),S.id,S.eligible,S.keep, ...
        'VariableNames',{'Group','Subject','Eligible_after_cleaning','Included_after_balancing'})];
    rawTable=[table(S.id,'VariableNames',{'Subject'}), ...
        array2table(S.raw,'VariableNames',cellstr(S.names))];
    cleanTable=[table(S.id,'VariableNames',{'Subject'}), ...
        array2table(S.cleaned,'VariableNames',cellstr(S.names))];
    writetable(rawTable,fullfile(datadir,sprintf('%s_Group%d_Raw.csv',safe_name,g)));
    writetable(cleanTable,fullfile(datadir,sprintf('%s_Group%d_Cleaned.csv',safe_name,g)));
    writetable(cleanTable(S.keep,:),fullfile(datadir,sprintf('%s_Group%d_Analyzed.csv',safe_name,g)));
    fprintf('%s: %d matched, %d eligible, %d analyzed.\n',GROUP_LABELS(g),n,sum(S.eligible),sum(S.keep));
end
writetable(matching,stats_xlsx,'Sheet','Matching');
writetable(cleaning,stats_xlsx,'Sheet','Cleaning');
writetable(selection,stats_xlsx,'Sheet','Participant_inclusion');

%% QUESTIONNAIRE GROUP COMPARISON: WELCH T-TEST
qA=G{1}.cleaned(G{1}.keep,1); qB=G{2}.cleaned(G{2}.keep,1);
t=NaN; df=NaN; p=NaN; ci=[NaN NaN];
if numel(qA)>=2&&numel(qB)>=2
    [~,p,ci,st]=ttest2(qA,qB,'Vartype','unequal'); t=st.tstat; df=st.df;
end
GroupComparison=table(string(QUESTIONNAIRE_NAME),GROUP_LABELS(1),numel(qA), ...
    mean(qA),std(qA),GROUP_LABELS(2),numel(qB),mean(qB),std(qB), ...
    t,df,p,ci(1),ci(2),'VariableNames', ...
    {'Questionnaire','Group_A','N_A','Mean_A','SD_A','Group_B','N_B','Mean_B','SD_B', ...
     't','df','p_raw','Difference_CI_low','Difference_CI_high'});
writetable(GroupComparison,stats_xlsx,'Sheet','Questionnaire_group_comparison');

%% CORRELATIONS: FIXED FAMILIES PER QUESTIONNAIRE
Correlation_Table=table(); outcomes=["Accuracy","LearningRate","Lambda"];
family_sizes=[12 12 4];
for o=1:3
    np=3;
    if o==3, np=1; end
    for c=1:2
        for g=1:2
            Y=G{g}.cleaned(G{g}.keep,:); x=Y(:,1);
            for b=1:np
                if o==1, column=1+(c-1)*3+b; pred=PREDICTABILITY(b);
                elseif o==2, column=7+(c-1)*3+b; pred=PREDICTABILITY(b);
                else, column=13+c; pred="Overall"; end
                st=local_correlation(x,Y(:,column)); pb=NaN;
                if isfinite(st.p), pb=min(st.p*family_sizes(o),1); end
                row=table(GROUP_LABELS(g),CONDITION_LABELS(c),string(QUESTIONNAIRE_NAME), ...
                    outcomes(o),pred,st.N,st.r,st.p,st.lo,st.hi,st.r^2,st.p,pb, ...
                    family_sizes(o),ALPHA/family_sizes(o), ...
                    isfinite(st.p)&&st.p<ALPHA,isfinite(pb)&&pb<ALPHA, ...
                    'VariableNames',{'Group','Condition','Questionnaire','Outcome','Predictability', ...
                    'N','r','p','CI_low','CI_high','R2','p_raw','p_bonf','Bonferroni_tests', ...
                    'Alpha_bonf','Significant_raw','Significant_bonf'});
                Correlation_Table=[Correlation_Table;row];
            end
        end
    end
end
writetable(Correlation_Table,stats_xlsx,'Sheet','Correlations');
writetable(Correlation_Table,fullfile(statsdir,[safe_name,'_Correlations_All.csv']));

%% FIGURES: SIX ACCURACY/LR PANELS AND TWO LAMBDA PANELS
outcome_labels=["Accuracy (%)","Learning rate","Volatility update rate"];
for o=1:3
    np=3; conditions=1:2;
    if o==3, np=1; end
    for b=1:np
        if o<3
            plotConditions={conditions};
        else
            plotConditions={1,2};
        end
        for f=1:numel(plotConditions)
            cs=plotConditions{f};
            fig=figure('Color','w','Position',[100 100 1050 700]);
            ax=axes(fig); hold(ax,'on'); handles=gobjects(2*numel(cs),1);
            legends=strings(2*numel(cs),1); r=0;
            for c=cs
                for g=1:2
                    r=r+1; Y=G{g}.cleaned(G{g}.keep,:); x=Y(:,1);
                    if o==1, column=1+(c-1)*3+b; pred=PREDICTABILITY(b);
                    elseif o==2, column=7+(c-1)*3+b; pred=PREDICTABILITY(b);
                    else, column=13+c; pred="Overall"; end
                    y=Y(:,column); keep=isfinite(x)&isfinite(y); x=x(keep); y=y(keep);
                    handles(r)=scatter(ax,x,y,50,colors(g,:,c),'filled', ...
                        'MarkerEdgeColor','k','MarkerFaceAlpha',0.85);
                    legends(r)=GROUP_LABELS(g)+" ("+CONDITION_LABELS(c)+")";
                    if numel(x)>=2&&std(x)>0
                        coeff=polyfit(x,y,1); xx=linspace(min(x),max(x),100);
                        plot(ax,xx,polyval(coeff,xx),'Color',colors(g,:,c), ...
                            'LineWidth',2,'HandleVisibility','off');
                    end
                    ix=Correlation_Table.Group==GROUP_LABELS(g)& ...
                        Correlation_Table.Condition==CONDITION_LABELS(c)& ...
                        Correlation_Table.Outcome==outcomes(o)&Correlation_Table.Predictability==pred;
                    st=Correlation_Table(ix,:);
                    note=sprintf('%s: r = %.2f, p_raw = %.2g, p_Bonf = %.2g, N = %d', ...
                        legends(r),st.r,st.p_raw,st.p_bonf,st.N);
                    text(ax,0.02,0.98-(r-1)*0.06,note,'Units','normalized', ...
                        'VerticalAlignment','top','Color',colors(g,:,c),'FontSize',10,'Interpreter','none');
                end
            end
            xlabel(ax,QUESTIONNAIRE_LABEL,'FontSize',18,'Interpreter','none');
            ylabel(ax,outcome_labels(o),'FontSize',18);
            if o<3, plotTitle=string(QUESTIONNAIRE_NAME)+" | "+pred+" | "+outcomes(o);
            else, plotTitle=string(QUESTIONNAIRE_NAME)+" | "+CONDITION_LABELS(cs)+" | Lambda"; end
            title(ax,plotTitle,'FontSize',20,'Interpreter','none');
            ax.FontSize=16; ax.LineWidth=1.5; ax.TickDir='out'; ax.Box='off';
            limits=Y_LIMITS{o};
            if ~isempty(limits), ylim(ax,limits); end
            xl=xlim(ax); yl=ylim(ax);
            ax.XTick=linspace(xl(1),xl(2),5); ax.YTick=linspace(yl(1),yl(2),5);
            legend(ax,handles,cellstr(legends),'Location','eastoutside','Box','off','Interpreter','none');
            if o<3, name=sprintf('%s_%s_%s',safe_name,outcomes(o),pred);
            else, name=sprintf('%s_Lambda_Condition%d',safe_name,cs); end
            exportgraphics(fig,fullfile(figdir,[name,'.png']),'Resolution',PNG_DPI);
            exportgraphics(fig,fullfile(figdir,[name,'.pdf']),'ContentType','vector');
        end
    end
end
save(fullfile(datadir,[safe_name,'_AllOutputs.mat']),'G','Correlation_Table','GroupComparison', ...
    'matching','cleaning','selection','QUESTIONNAIRE_NAME','QUESTIONNAIRE_LABEL','questionnaire_files', ...
    'accuracy_files','vkf_files','BLOCK_COL','ACC_COL','BLOCK_SETS','QUESTIONNAIRE_SHEET', ...
    'QUESTIONNAIRE_SCORE_COLUMN','QUESTIONNAIRE_ID_COLUMN','VKF_ID_FIELD','APPLY_3SD', ...
    'SD_THRESHOLD','BALANCE_GROUPS','BALANCE_METHOD','RANDOM_SEED','ALPHA','Y_LIMITS');
fprintf('Completed %s. Results: %s\n',QUESTIONNAIRE_NAME,outdir);

%% LOCAL HELPERS
function S=local_read_session(behaviorFile,vkfFile,blockColumn,accuracyColumn,blockSets,idField)
    assert(isfile(behaviorFile),'Missing behavioral file: %s',behaviorFile);
    assert(isfile(vkfFile),'Missing VKF file: %s',vkfFile);
    sheets=string(sheetnames(behaviorFile)); sheets=sheets(:);
    ids=local_ids(sheets,behaviorFile); V=load(vkfFile);
    assert(isfield(V,'kgain_mat')&&isfield(V,'lambda_vec'), ...
        'VKF file must contain kgain_mat and lambda_vec: %s',vkfFile);
    assert(isnumeric(V.kgain_mat)&&ismatrix(V.kgain_mat)&&isnumeric(V.lambda_vec)&&isvector(V.lambda_vec), ...
        'Invalid VKF array types or dimensions in %s.',vkfFile);
    lr=double(V.kgain_mat); lambda=double(V.lambda_vec(:));
    if isfield(V,idField)
        vid=local_ids(string(V.(idField)),vkfFile);
        assert(numel(vid)==size(lr,1)&&numel(vid)==numel(lambda),'VKF ID/row count mismatch: %s',vkfFile);
        [found,rows]=ismember(ids,vid);
        assert(all(found),'Some behavior IDs have no VKF row: %s',vkfFile);
    else
        assert(size(lr,1)==numel(ids)&&numel(lambda)==numel(ids), ...
            'VKF rows must equal workbook sheet count when subject_ids is absent: %s',vkfFile);
        rows=(1:numel(ids)).';
    end
    A=nan(numel(ids),3); L=A; lam=lambda(rows); lam(~isfinite(lam))=NaN;
    for i=1:numel(ids)
        T=readtable(behaviorFile,'Sheet',sheets(i),'VariableNamingRule','preserve');
        assert(width(T)>=max(blockColumn,accuracyColumn),'Insufficient columns in %s, sheet %s.',behaviorFile,sheets(i));
        blocks=local_blocks(string(T{:,blockColumn})); acc=local_accuracy(T{:,accuracyColumn},behaviorFile,sheets(i));
        gains=lr(rows(i),:).'; n=height(T);
        assert(numel(gains)>=n,'VKF has fewer trial columns than behavioral rows: %s, %s.',vkfFile,sheets(i));
        if numel(gains)>n
            assert(all(isnan(gains(n+1:end))), ...
                'Extra VKF trial columns must be NaN padding: %s, %s.',vkfFile,sheets(i));
        end
        gains=gains(1:n); gains(~isfinite(gains))=NaN;
        for p=1:3
            mask=ismember(blocks,local_blocks(blockSets{p}));
            A(i,p)=100*mean(acc(mask),'omitnan'); L(i,p)=mean(gains(mask),'omitnan');
        end
    end
    S=struct('id',ids,'accuracy',A,'lr',L,'lambda',lam);
end
function Q=local_read_questionnaire(file,sheet,scoreColumn,idColumn)
    assert(isfile(file),'Missing questionnaire file: %s',file);
    C=readcell(file,'Sheet',sheet);
    assert(size(C,2)>=max(scoreColumn,idColumn),'Missing questionnaire columns: %s',file);
    score=local_numeric(C(:,scoreColumn));
    if ~isempty(score)&&~isfinite(score(1))
        first=C{1,scoreColumn}; isHeader=(ischar(first)||isstring(first));
        if isHeader
            label=lower(strtrim(string(first)));
            isHeader=~ismissing(label)&&label~=""&&~ismember(label,["nan","na","n/a","missing"]);
        end
        if isHeader, C=C(2:end,:); score=score(2:end); end
    end
    score(~isfinite(score))=NaN; ids=strings(0,1);
    if idColumn>0, ids=local_ids(string(C(:,idColumn)),file); end
    Q=struct('id',ids,'score',score(:));
end
function x=local_numeric(raw)
    if isnumeric(raw)||islogical(raw), x=double(raw(:)); return; end
    x=nan(numel(raw),1);
    for k=1:numel(raw)
        if iscell(raw), value=raw{k}; else, value=raw(k); end
        if (isnumeric(value)||islogical(value))&&isscalar(value), x(k)=double(value);
        elseif ischar(value)||isstring(value), x(k)=str2double(string(value)); end
    end
end
function x=local_accuracy(raw,file,sheet)
    if isnumeric(raw)||islogical(raw)
        x=double(raw(:)); bad=isfinite(x)&x~=0&x~=1;
    else
        labels=lower(strtrim(string(raw))); labels=labels(:); x=nan(size(labels));
        x(ismember(labels,["correct","true","1"]))=1;
        x(ismember(labels,["incorrect","false","0"]))=0;
        missingLabel=ismissing(labels)|ismember(labels,["","nan","na","n/a","missing"]);
        bad=isnan(x)&~missingLabel;
    end
    assert(~any(bad),'Unexpected correctness values in %s, sheet %s.',file,sheet);
    x(~isfinite(x))=NaN;
end
function ids=local_ids(raw,file)
    ids=regexprep(upper(strtrim(string(raw(:)))),'_S[12]$','');
    assert(~any(ismissing(ids)|ids=="")&&numel(unique(ids))==numel(ids), ...
        'Empty or duplicate normalized IDs in %s.',file);
end
function blocks=local_blocks(raw)
    blocks=lower(regexprep(strtrim(string(raw)),'\s+',''));
end
function [x,flagged,lo,hi]=local_clean(x,threshold)
    finite=isfinite(x); flagged=false(size(x)); lo=NaN; hi=NaN;
    if sum(finite)>=3
        mu=mean(x(finite)); sd=std(x(finite)); lo=mu-threshold*sd; hi=mu+threshold*sd;
        if sd>0, flagged=finite&(x<lo|x>hi); end
    end
    x(~finite|flagged)=NaN;
end
function st=local_correlation(x,y)
    keep=isfinite(x)&isfinite(y); x=x(keep); y=y(keep); n=numel(x);
    st=struct('N',n,'r',NaN,'p',NaN,'lo',NaN,'hi',NaN);
    if n>=3&&std(x)>0&&std(y)>0
        [st.r,st.p]=corr(x,y,'Type','Pearson');
        if n>3
            if abs(st.r)>=1, st.lo=st.r; st.hi=st.r;
            else
                z=atanh(st.r); margin=norminv(0.975)/sqrt(n-3);
                st.lo=tanh(z-margin); st.hi=tanh(z+margin);
            end
        end
    end
end
