
*********************************************************************************
 Program: Quantitative analysis project.sas                                               
 
                                                           
 Description: Takes the crspm_small dataset which is the full set of monthly
 returns from CRSP and examines the gross profit and value anomaly with sorts and graphs using
 the Subroutine_ Form Portfolios and Test Anomaly
                         
*********************************************************************************;



*******************************************************;
***Clean Slate: Clear Log and Empty Work Directory;
*******************************************************;

/* 	dm 'log;clear;'; *NOT NECESSARY FOR SAS STUDIO*/
	proc datasets library = work kill memtype=data nolist;
	  quit;



*******************************************************;
**Libraries and Paths;
*******************************************************;
**Define your paths;

%let data_path=/home/u63319719/sasuser.v94/Quantitative Analysis Project;
%let program_path=/home/u63319719/sasuser.v94/Quantitative Analysis Project;
%let output_path=/home/u63319719/sasuser.v94/Quantitative Analysis Project;


*Define Data library;
libname my "&data_path";

*******************************************************;
*Get Stock Data Ready
*******************************************************;



*Make temporary version of full stock universe and create any extra variables you want to add to the mix;
data stock;
set my.crspm_small;
by permno;


*Create/change any variables
***********************************************************************;
*fix price variable because it is sometimes negative to reflect average of bid-ask spread;
price=abs(prc);
*get beginning of period price;
lag_price=lag(price);
if first.permno then lag_price=.;
***********************************************************************;


/* if LME=. then delete; *require all stocks to have beginning of period market equity.; */
if primary_security=1; *pick only the primary security as of that date (only applies to multiple share class stocks);

keep date permno ret lag_price me lme;
*remove return label to make programming easier;
label ret=' ';

run;  
*************************************************************;
*do any extra stuff to get your formation data ready;
*************************************************************;


***********************Compustat Book equity Fama French Style
Compustat XpressFeed Variables:                                     
AT      = Total Assets                                              
PSTKL   = Preferred Stock Liquidating Value                                     
PSTKRV  = Preferred Stock Redemption Value       
PSTK	= Preferred Stock Par Value
TXDITC  = Deferred Taxes and Investment Tax Credit       
SEQ		= Shareholder's Equity
CEQ     = Common/Ordinary Equity - Total  
LT 		= Total Liabilities 
datadate = Date of fiscal year end

**********************************************************************
 ;
*
*Define book equity Fama French Style:


BE is the book value of stockholders� equity, plus balance sheet deferred taxes
and investment tax credit (if available), minus the book value of preferred stock. 
Depending on availability, we use the redemption, liquidation, or par value (in that order)
to estimate the book value of preferred stock. Stockholders� equity is the value reported
by Moody�s or Compustat, if it is available. If not, we measure stockholders� equity as the
book value of common equity plus the par value of preferred stock, or the book value of assets
minus total liabilities (in that order). 

http://mba.tuck.dartmouth.edu/pages/faculty/ken.french/Data_Library/variable_definitions.html

;

*Get Compustat Data ready; 
data account;
set my.comp_big;

*data is already sorted on WRDS so we can use by groups right away;
  by gvkey datadate;


*How to Define variables based on what data is available >> use coalesce function
coalesce(x,y,z) function takes the first nonmissing value of the list of variables you give it, delimited by commas;

*Calculate Stockholder's Equity;
/*   SE=coalesce(SEQ, CEQ+PSTK, AT - LT); */

*Calculate Book value of Preferred Stock;
/*   PS = coalesce(PSTKRV,PSTKL,PSTK,0); */
  
*Calculate balance sheet deferred taxes and investment tax credit;
/*   if missing(TXDITC) then TXDITC = 0 ; */

*Define BOOK Equity according to Fama French Definition!;
/*   BE = SE + TXDITC - PS ; */

*set Negative book equity to missing;
/*   if BE<0 then BE=.; */

GP = coalesce(REVT-COGS,SALE-COGS,EBITDA+XSGA);
if GP<0 then GP=.; 
label 
GP="Gross Profit Fama French"

;

*require the stock to have a PERMNO (a match to CRSP);
if permno=. then delete;
*only keep the variables we need for later;
keep datadate permno GP AT;

*keep datadate permno GP at lt ;
run;


*Merge stock returns data from CRSP with book equity accounting data from Compustat.
For each month t in the stock returns set, merge with the latest fiscal year end that is also at least 6 months old so we can 
assume you would have access to the accounting data. Remember that firms report accounting data with a lag, annual data in year t
won't be reported until annual reports come out in April of t+1. This sorts by datadate_dist so that closest dates come first;

proc sql;
create table formation as
select a.*, b.* , intck('month',b.datadate,a.date) as datadate_dist "Months from last datadate"

from stock a, account b
where a.permno=b.permno and 6 <= intck('month',b.datadate,a.date) <=18
order by a.permno,date,datadate_dist;
quit;

*select the closest accounting observation for each permno and date combo;
data formation;
set formation;
by permno date;
if first.date;

*Define Book to market ratio! 
-Use beginning of period market equity and BE from 6 to 18 months old)
-Unlike Fama French, we use recent Market Equity following Asness and Frazzini 2014 Devil in HML Details ;

GPA=GP/AT;

run;

*Get SIC industry code from header file in order to
remove stocks that are classified as financials because they have weird ratios (avoid sic between 6000-6999);
proc sql;
create table formation as
select a.*, b.siccd
from formation a ,my.msenames b
where a.permno=b.permno and (b.NAMEDT <= a.date <=b.NAMEENDT)
and not (6000<= b.siccd <=6999);
quit;

*******************************************************;
*Define your Anomaly (User Input required here)
*******************************************************;

*Define a Master Title that will correspond to Anomaly definition throughout output;
title1 "Gross Profit Effect";
*Start Output file;
ods pdf file="&output_path/Gross Profit Effect.pdf"; 

*Define the variable you want to sort on and define your subsample criteria
For instance, you may only want to form portfolios every July (once a year), so we would just keep 
those stocks to form our portfolios. If we build them every month we wouldn't need the restriction
;
data formation;
set formation;
by permno date;

***********************************************************************;
*Define the stock characteristics you want to sort on (SORTVAR);
***********************************************************************;
SORTVAR=GPA; *Gross Profit to Assets Ratio;
format SORTVAR 10.3;
label SORTVAR="Sort Variable: Gross Profit and Assets Ratio";

***********************************************************************;
*Define Rebalance Frequency;
***********************************************************************;
if month(date)=7; *Rebalance Annually in July;
*if month(date) in (3,6,9,12); *Rebalance every calendar quarter;
*if month(date) ne . ; *Rebalance every month;

***********************************************************************;
*Define subsample criteria
***********************************************************************;
if SORTVAR = . then delete; *must have non missing SORTVAR;
if year(date)>=1983 and year(date)<=2022; *Select Time period;
if lme>1; *market cap of at least 1 million to start from;
if lag_price<1 or lag_price=. then delete; *Remove penny stocks or stocks missing price;

***********************************************************************;
*Define portfolio_weighting technique;
***********************************************************************;
portfolio_weight=LME; *Portfolio weights: set=1 for equal weight, or set =LME for value weighted portfolio;

run;



*******************************************************;
*Define holding period, bin Order and Format
*******************************************************;
*Define Holding Period (number of months in between rebalancing dates (i.e., 1 year = 12 months);
%let holding_period = 12;

*Define number of bins;
%let bins=5;

*Define the bin ordering:;
*%let rankorder= ; 
%let rankorder=descending;

*What stocks are you going long vs. what are you going Short?
leave blank for ascending rank (bin 1 is smallest value), set to descending 
if you want bin 1 to have largest value;

*Define a bin format for what the bin portfolios will correspond to for output;
proc format;
value bin_format 1="1. High Gross Profit to Assets"
5="5. Low Gross Profit to Assets"
99="Long/Short: High - Low"
;
run;




**********************************************************Forming Portfolios and Testing Begins Here**************************************;
%include "&program_path/Subroutine_ Form Portfolios and Test Anomaly.sas";

ods pdf close;

data gross_profit;
set portfolio;
where bin=99;
run;


** Part III**;





**1. Create dataset - wide**;
data wide;
set gross_profit;
value_momentum = hml + umd;
gross_profit_plus_value = hml + exret;
label value_momentum ='Value plus Momentum';
label gross_profit_plus_value ='Gross profit plus Value';
run;

**2. Transpose wide to long **;
proc transpose data=wide out=long;
by dateff;
var mktrf hml smb umd value_momentum gross_profit_plus_value;
run;


**3. Creating dataset portfolio **;
data portfolio_temp (RENAME=(dateff=date _LABEL_=bin COL1=exret) KEEP=dateff _LABEL_ COL1);
set long;
run;

**4. Merge Portfolio and factors monthly **;
proc sql;
create table final_portfolio as
select a.*, a.exret + b.rf as ret,b.*
from portfolio_temp as a, my.factors_monthly as b
where a.date=b.dateff
order by bin,a.date;
quit;


**5. Compound total returns for each bin and graph**;

data portfolio_graph;
set final_portfolio;
where bin in ("Value plus Momentum", "Gross profit plus Value");
by bin;

if first.bin then cumret1=10000;
if ret ne . then cumret1=cumret1*(1+ret);
else cumret1=cumret1;
cumret=cumret1-1;
retain cumret1;


format cumret1 dollar15.2 ; 
label cumret1="Value of Dollar Invested In Portfolio";

run;

*Graph Cumulative Performance with Log Scale;
proc sgplot data=portfolio_graph ;

   title 'Strategy comparsion: Cumulative Performance';
   footnote 'Log Scale';
   series x=date y=cumret1 / group=bin lineattrs=(thickness=2);
Xaxis type=time ;
Yaxis type=log logbase=10 logstyle=linear ; *log based scale;
     
run;

proc print data=portfolio_graph (keep= date bin cumret1) label;
where date='30DEC2022'd;
label
date='Portfolio on Date'
bin='Strategy'
cumret1='Portfolio Value';
format date date9.;
title1 "Comparison between the Strategies";
title2 "Portfolio Final Value";
run;



**6. Calculate Sharpe Ratios and Print **;

proc means data=final_portfolio n mean median std min max p1 skew ;
where bin in ("Value plus Momentum", "Gross profit plus Value");
by bin;
var ret ;
/* output out=mean_std mean= std= /autoname autolabel; */
run; 
*!EXAMINE THE RETURNS AND STANDARD DEVIATION;

proc means data=final_portfolio noprint;
where bin in ("Value plus Momentum", "Gross profit plus Value");
by bin;
var exret ;
output out=mean_std mean= std= /autoname autolabel; */
run; 


data sharpe;
set mean_std;

sharpe_ratio=exret_mean/exret_StdDev;
label 
exret_mean="Mean Excess Return"
exret_StdDev="Standard Deviation of Excess Returns"
sharpe_ratio="Sharpe Ratio"
;

format exret_mean exret_StdDev percentn10.2 sharpe_ratio 10.2;
drop _type_ _freq_;


run;

proc print noobs label;
title "Stratgey comparison: Sharpe Ratio by bin";
run;


** Question 4**;

*CAPM regression;
proc reg data = final_portfolio outest = CAPM_out edf noprint tableout;
by bin;
model exret = mktrf;
quit;

*CAPM clean up regression output;
data CAPM_out;
set CAPM_out;
where  _TYPE_ in ('PARMS','T') and bin in ("Value plus Momentum", "Gross profit plus Value"); *just keep Coefficients (Parms) and T-statistics (T);

*rescale intercept to percentage but only the PARMS, not T (Cant use percentage format because it would change T-stat also);
IF _TYPE_ ='PARMS' THEN intercept=intercept*100;

label 
intercept="Alpha: CAPM"
mktrf="Market Beta: CAPM"
;

format intercept mktrf 10.2;

keep bin _type_ intercept mktrf;

rename
intercept=alpha_capm
mktrf=mktrf_capm
;
run;


*Fama French 3 Factor;
proc reg data = final_portfolio outest = FF3_out edf noprint tableout;
by bin;
model exret = mktrf smb hml;
quit;


*FAMA FRENCH ALPHA AND BETAS*;
data FF3_out;
set FF3_out;
where  _TYPE_ in ('PARMS','T');

*rescale intercept to percentage but only the PARMS, not T;
IF _TYPE_ ='PARMS' THEN intercept=intercept*100;

label 
intercept="Alpha: FF3"
mktrf="Market Beta: FF3"
smb="SMB Beta"
hml="HML Beta"
;

format intercept mktrf smb hml 10.2;

keep bin _type_ intercept mktrf smb hml;

rename 
intercept=alpha_ff3
mktrf=mktrf_ff3
;

run;

*MERGE TOGETHER FOR NICE TABLE;
data Nice_table ;
retain bin;
merge CAPM_out FF3_out;
by bin _type_;
where bin in ("Value plus Momentum", "Gross profit plus Value");

format bin bin_format.;
run;

proc print;
title "Comparison between strategies: Factor Regression Results";
run;


** Question 5.1 **;

data final_portfolio_annual;
set final_portfolio;
where bin in ("Value plus Momentum", "Gross profit plus Value");
by bin;
if first.bin then cumret1=1;
if month=1 then cumret1=1;
if ret ne . then cumret1=cumret1*(1+ret);
else cumret1=cumret1;
cumret=cumret1-1;
retain cumret1;
format cumret percentn10.2 ; 
label cumret="Annual Cumulative Return";
run;

data final_portfolio_annual_summary;
set final_portfolio_annual;
if month=12;
run;

proc sort data=final_portfolio_annual_summary;
by year;
run;


proc print data=final_portfolio_annual_summary (keep=bin year cumret);
title1 "Comparison between the Strategies";
title2 "Annual Strategy Performance";
run;

proc sgplot data=final_portfolio_annual_summary;
title1 "Comparison between the Strategies";
series x=year y=cumret / group=bin lineattrs=(thickness=2);
Xaxis type=time;
run;



proc transpose data=final_portfolio_annual_summary out=final_portfolio_annual_table (drop=_NAME_ _LABEL_);
by year;
var cumret;
id bin;
run;



proc print data=final_portfolio_annual_table ;
title "Annual returns comparison for both strategies";
run;

** Question 5.2 **;

proc sort data=final_portfolio_annual_summary;
by bin descending cumret;
run;

proc rank data=final_portfolio_annual_summary out=Ranked_annual_returns descending;
by bin;
var cumret;
ranks cumret_rank;
run;


proc sort data=Ranked_annual_returns out=Best_5_returns (keep= bin year cumret cumret_rank);
by bin;
where cumret_rank <=5;
run;

proc print data=Best_5_returns label;
title "5 Best annual returns";
run;


proc sort data=Ranked_annual_returns out=Worst_5_returns (keep= bin year cumret cumret_rank);
by bin descending cumret_rank;
where cumret_rank >=35;
run;

proc print data=Worst_5_returns label;
title "5 Worst annual returns";
run;

** Question 5.3 **;

proc sort data=final_portfolio_annual_summary;
by descending cumret;
run;

proc rank data=final_portfolio_annual_summary out=Ranked_annual_returns_overall descending;
var cumret;
ranks cumret_rank;
run;


proc sort data=Ranked_annual_returns_overall out=Best_5_returns_overall (keep= bin year cumret cumret_rank);
by descending cumret_rank;
where cumret_rank <=5;
run;



proc sort data=Ranked_annual_returns_overall out=Worst_5_returns_overall (keep= bin year cumret cumret_rank);
by cumret_rank;
where cumret_rank >75;
run;




proc sgplot data=Best_5_returns_overall;
title "Five Best Returns Overall";
vbar cumret_rank / response=cumret datalabel=bin;
run;

proc sgplot data=Worst_5_returns_overall;
title "Five Worst Returns Overall";
vbar cumret_rank / response=cumret datalabel=bin;
run;


** Question 5.4 **;

data final_portfolio_monthly;
set final_portfolio;
where bin in ("Value plus Momentum", "Gross profit plus Value");
by bin;
ind = 0;
if ret>0 then ind=1;
run;

proc sort data=final_portfolio_annual_summary ;
by bin;
run;

data final_portfolio_annually;
set final_portfolio_annual_summary;
where bin in ("Value plus Momentum", "Gross profit plus Value");
by bin;
ind = 0;
if cumret>0 then ind=1;
run;




proc sql;
create table return_indicators_monthly as
select distinct bin,
sum(ind)/count(month) as per_pos_months
from final_portfolio_monthly
group by bin
order by bin;
quit;

proc sql;
create table return_indicators_yearly as
select distinct bin,
sum(ind)/count(year) as per_pos_years
from final_portfolio_annually
group by bin
order by bin;
quit;


proc sql;
create table return_indicators_calculation as
select distinct a.bin, 
a.per_pos_months, 
b.per_pos_years
from return_indicators_monthly as a, return_indicators_yearly as b
where a.bin=b.bin
group by a.bin
order by a.bin;
quit;

data return_indicators_labelled;
set return_indicators_calculation;
label per_pos_months='% of Positive Months';
label per_pos_years='% of Positive Years';
run;

proc print data=return_indicators_labelled label;
title "Positive Return Months and Years (%)";
format per_pos_months per_pos_years percent10.2;
run;
