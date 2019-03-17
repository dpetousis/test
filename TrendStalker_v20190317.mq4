//+------------------------------------------------------------------+
//|                        Copyright 2018, Dimitris Petousis         |
//+------------------------------------------------------------------+
#property strict

// DEFINITIONS & ENUMS ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#define NAMESNUMBERMAX 20                 // this is the max number of names currently - it can be set higher if needed
#define TRADESPERNAMEMAX 2
enum BOLLINGERMODE {
	NONE = 0, //NONE
	UPPER = 1, //MODE_UPPER
	LOWER = 2, //MODE_LOWER
};
enum INPUTFILENAME {
	TF_DEMO_H1 = 0, //TF_DEMO_H1
	TF_DEMO_H4 = 1, //TF_DEMO_H4
	TF_REAL_H1 = 2, //TF_REAL_H1
	TF_REAL_H4 = 3, //TF_REAL_H4
	AM_DEMO_H1 = 4, //AM_DEMO_H1
	AM_DEMO_M5 = 5, //AM_DEMO_M5
};

// INPUTS ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//input switches & program constants
extern bool b_noNewSequence = false;
input INPUTFILENAME inputFilenameIndex = TF_REAL_H1; 
input double const bollinger_deviations = 4;
input BOLLINGERMODE bollinger_mode = UPPER;
input int const bollinger_delay = 5;
input double const f_percWarp = 0.3;
input double const f_percTP = 1;
input bool const b_verbose = true;
int i_stratMagicNumber = -1; // dummy initialisation  
// statistics parameters
bool const b_statistics = true;
double const f_barSizePortion = 0.25;  // Gap = variable * (average bar size)
int const i_bandsHistory = 2000;       // history for averaging (both bars and bands)
int const filter_history = 50;		// fast filter history
// trading parameters
double const f_percSL = 1;
double const f_percAvBandSeparation = 1;  // pips to SL (or TP) = variable * ([average upper band] - [average lower band])
double const f_minBollingerBandRatio = 0.125;    // [min upper band] = [central band] + ratio * ([average upper band] - [average lower band])
double const f_adjustLevel = 1; //0.1; with 1, it basically never adjusts
int const slippage =10;           // in points
// credit parameters
double const f_creditPenalty = 100.0;
double const f_creditPenaltyThreshold = 10.0;

// TRADE ACCOUNTING VARIABLES ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
int const timeFrame=Period();    
int i_namesNumber=0,i_ordersTotal = 0,i_openSequenceForProduct=-1;
bool b_accountingWriteDone=false,b_pendingGlobal=false,b_openManualSequence=false;
int m_myMagicNumber[NAMESNUMBERMAX];  // Magic Numbers
double m_accountCcyFactors[NAMESNUMBERMAX];
double m_sequence[NAMESNUMBERMAX][7];   // 0:SF,1:Losses excl current,2:#,3:warp,4:SL,5:TP,6:FF freq
string m_names[NAMESNUMBERMAX];
string const m_commentTradeFlag[TRADESPERNAMEMAX] = {"A","B"};
double m_bollingerDeviationInPips[];   // [average upper band] - [average lower band]
bool m_tradeFlag[];
double m_filter[][3];      // vwap,filter freq
double m_profitInAccCcy[];
int m_lotDigits[];
double m_lotMin[];
int m_ticket[][TRADESPERNAMEMAX];
int m_tradesNumber[];        // 1:single trade 2:split trades
double m_cumLosses[];
double m_bandsTSAvg[];
double m_creditAmount[];
double f_creditBalance = 0.0;
double m_barTSAvg[];
double m_slowFilterGap[];     // Gap = upper SF - SF = SF - lower SF

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   double f_overlap,f_low1,f_low2,f_high1,f_high2,f_scale,f_barSizeTSAvg = 0.0;
   double temp_sequence[8]={0,0,0,0,0,0,0,0};
   int temp_tickets[2];
   string s_namesRemoved = "", s_namesOpen = "", s_symbolAppendix = "";
   bool b_readLastWeekDataFromTradePopulation=false;
   i_ordersTotal = OrdersTotal();
   
   // STRATEGY NUMBER
   if (timeFrame == 5) { i_stratMagicNumber = 50 + bollinger_mode; } // M5: 50
   else { i_stratMagicNumber = (10*timeFrame/60) + bollinger_mode; }  // H1,H4: 10,40
   
   // TIMER FREQUENCY - APPARENTLY NO SERVER CONTACT FOR MORE THAN 30SEC WILL CAUSE REAUTHENTICATION ADDING CONSIDERABLE DELAY, SO THEREFORE USE 15SEC INTERVAL
   if (timeFrame == 5) { EventSetTimer(10); }
   else { EventSetTimer(15); }
   
   // READ IN THE FILE
   string m_rows[20];
   ushort u_sep=StringGetCharacter(",",0);
   int temp,i_tradesPerName;
   string arr[];
   int filehandle=FileOpen(EnumToString(inputFilenameIndex)+".txt",FILE_READ|FILE_TXT);
   if(filehandle!=INVALID_HANDLE) {
      FileReadArray(filehandle,arr);
      FileClose(filehandle);
      Print("FileOpen OK");
   }
   else PrintFormat("Failed to open %s file, Error code = %d",EnumToString(inputFilenameIndex)+".txt",GetLastError());
   i_namesNumber = ArraySize(arr);
   
   // Resize arrays once number of products known
   ArrayResize(m_names,i_namesNumber,0);
   ArrayResize(m_sequence,i_namesNumber,0);
   ArrayResize(m_myMagicNumber,i_namesNumber,0);
   ArrayResize(m_accountCcyFactors,i_namesNumber,0);
   ArrayResize(m_bollingerDeviationInPips,i_namesNumber,0);
   ArrayResize(m_tradeFlag,i_namesNumber,0);
   ArrayResize(m_filter,i_namesNumber,0);
   ArrayResize(m_profitInAccCcy,i_namesNumber,0);
   ArrayResize(m_lotDigits,i_namesNumber,0);
   ArrayResize(m_lotMin,i_namesNumber,0);
   ArrayResize(m_ticket,i_namesNumber,0);
   ArrayResize(m_bandsTSAvg,i_namesNumber,0);
   ArrayResize(m_creditAmount,i_namesNumber,0);
   ArrayResize(m_tradesNumber,i_namesNumber,0);
   ArrayResize(m_cumLosses,i_namesNumber,0);
   ArrayResize(m_barTSAvg,i_namesNumber,0);
   ArrayResize(m_slowFilterGap,i_namesNumber,0);
   // Initialize arrays
   ArrayInitialize(m_sequence,0.0);
   ArrayInitialize(m_myMagicNumber,0);
   ArrayInitialize(m_accountCcyFactors,0.0);
   ArrayInitialize(m_bollingerDeviationInPips,0);
   ArrayInitialize(m_tradeFlag,false);
   ArrayInitialize(m_filter,0.0);
   ArrayInitialize(m_profitInAccCcy,0.0);
   ArrayInitialize(m_lotDigits,0.0);
   ArrayInitialize(m_lotMin,0.0);
   ArrayInitialize(m_ticket,0);
   ArrayInitialize(m_bandsTSAvg,0.0);
   ArrayInitialize(m_creditAmount,0.0);
   ArrayInitialize(m_tradesNumber,1);
   ArrayInitialize(temp_tickets,0);
   ArrayInitialize(m_cumLosses,0);
   ArrayInitialize(m_barTSAvg,0.0);
   ArrayInitialize(m_slowFilterGap,0.0);
      
   // read from files if they exist
   string const s_sequenceFileName = StringConcatenate("sequence_",IntegerToString(i_stratMagicNumber),".txt");
   string const s_ticketFileName = StringConcatenate("ticket_",IntegerToString(i_stratMagicNumber),".txt");
   string const s_cumLossesFileName = StringConcatenate("cumLosses_",IntegerToString(i_stratMagicNumber),".txt");
   string arr_sequence[], arr_ticket[], arr_volLosses[];
   if (FileIsExist(s_sequenceFileName,0) && FileIsExist(s_ticketFileName,0)) {
      filehandle=FileOpen(s_sequenceFileName,FILE_READ|FILE_TXT);
      if(filehandle!=INVALID_HANDLE) {
         FileReadArray(filehandle,arr_sequence);
         FileClose(filehandle);
      }
      else Alert("Failed to open ",s_sequenceFileName);
      filehandle=FileOpen(s_ticketFileName,FILE_READ|FILE_TXT);
      if(filehandle!=INVALID_HANDLE) {
         FileReadArray(filehandle,arr_ticket);
         FileClose(filehandle);
      }
      else Alert("Failed to open ",s_ticketFileName);
   }
   else { b_readLastWeekDataFromTradePopulation = true; }   // this mode means that things like updated slow filters or split flags will be lost when EA restarts
   if (FileIsExist(s_cumLossesFileName,0)) {
      filehandle=FileOpen(s_cumLossesFileName,FILE_READ|FILE_TXT);
      if(filehandle!=INVALID_HANDLE) {
         FileReadArray(filehandle,arr_volLosses);
         FileClose(filehandle);
      }
      else Alert("Failed to open ",s_cumLossesFileName); 
   }
   
   for(int i=0; i<i_namesNumber; i++) {
      
      // m_names array
      temp = StringSplit(arr[i],u_sep,m_rows);
      if (temp == ArraySize(m_rows)) {
         m_names[i] = m_rows[0];
         if (StringCompare(m_rows[1],"Y",false)==0) {
            m_tradeFlag[i] = true;
         }
         m_profitInAccCcy[i] = StringToDouble(m_rows[2]);
         m_filter[i][0] = StringToDouble(m_rows[3]);
         m_filter[i][1] = StringToDouble(m_rows[4]);   
         m_filter[i][2] = StringToDouble(m_rows[5]);
      }
      else { PrintFormat("Failed to read row number %d, Number of elements read = %d instead of %d",i,temp,ArraySize(m_rows)); }
      // magic numbers
      m_myMagicNumber[i] = getMagicNumber(m_names[i],i_stratMagicNumber);
      // lot details
      m_lotDigits[i] = (int)MathMax(-MathLog10(MarketInfo(m_names[i],MODE_LOTSTEP)),0);
      if (m_lotDigits[i]<0) { Alert("Lot digits calculation is wrong for ",m_names[i]); }
      m_lotMin[i] = MarketInfo(m_names[i],MODE_MINLOT);
      
      // STATISTICS
	   if (b_statistics && m_tradeFlag[i]) {
		  f_barSizeTSAvg = 0.0;
		  f_overlap = 0.0;
		  for (int j=0;j<i_bandsHistory;j++) {
			 // measure of bar size vs band width
			m_bandsTSAvg[i] = m_bandsTSAvg[i] + iBands(m_names[i],timeFrame,(int)m_filter[i][0],bollinger_deviations,0,0,MODE_UPPER,j+1) - 
								iBands(m_names[i],timeFrame,(int)m_filter[i][0],bollinger_deviations,0,0,MODE_LOWER,j+1);
			f_barSizeTSAvg = f_barSizeTSAvg + iHigh(m_names[i],timeFrame,j+1) - iLow(m_names[i],timeFrame,j+1);
			// neighbouring-bar overlap measure
			  f_low1 = MathMin(iClose(m_names[i],timeFrame,j+1),iOpen(m_names[i],timeFrame,j+1));
			f_low2 = MathMin(iClose(m_names[i],timeFrame,j+2),iOpen(m_names[i],timeFrame,j+2));
			f_high1 = MathMax(iClose(m_names[i],timeFrame,j+1),iOpen(m_names[i],timeFrame,j+1));
			f_high2 = MathMax(iClose(m_names[i],timeFrame,j+2),iOpen(m_names[i],timeFrame,j+2));
			f_scale = MathMax(iHigh(m_names[i],timeFrame,j+1),iHigh(m_names[i],timeFrame,j+2)) - MathMin(iLow(m_names[i],timeFrame,j+1),iLow(m_names[i],timeFrame,j+2));
			  f_overlap = f_overlap + MathMax((MathMin(f_high1,f_high2)-MathMax(f_low1,f_low2))/f_scale,0.0);
		  }
		  m_bandsTSAvg[i] = NormalizeDouble((1/MarketInfo(m_names[i],MODE_POINT)) * m_bandsTSAvg[i] / i_bandsHistory, 0); // in pips
		  if (b_verbose) { Alert(m_names[i]," Average band in pips: ",m_bandsTSAvg[i]); }
		  m_barTSAvg[i] = NormalizeDouble(f_barSizeTSAvg / i_bandsHistory, (int)MarketInfo(m_names[i],MODE_DIGITS));
		  f_barSizeTSAvg = NormalizeDouble((1/MarketInfo(m_names[i],MODE_POINT)) * f_barSizeTSAvg / i_bandsHistory, 0); // in pips
		  f_overlap = f_overlap / i_bandsHistory;
		  if (b_verbose) { Alert(m_names[i]," Ratio: ",f_barSizeTSAvg/m_bandsTSAvg[i]); }
		  /** if ((f_barSizeTSAvg/m_bandsTSAvg[i] > 0.11) && (m_sequence[i][0]<0)) {        // if noisy and no sequence already live -> exclude pair
			 m_tradeFlag[i] = false;
			 Alert(m_names[i]," removed. Ratio: ",f_barSizeTSAvg/m_bandsTSAvg[i]);
			 StringAdd(s_namesRemoved,m_names[i]);
			 StringAdd(s_namesRemoved,"_");
		  }   **/
		  if (b_verbose) { Alert(m_names[i]," Overlap Measure: ",f_overlap); }
      }
      
      // initialize m_sequence, m_ticket and m_tradesNumber
      if (b_readLastWeekDataFromTradePopulation) {
         m_sequence[i][0] = -1.0;      //Initialize to -1,0,0
         m_sequence[i][3] = f_percWarp;
         m_sequence[i][4] = f_percSL;
         m_sequence[i][5] = f_percTP;
         m_sequence[i][6] = m_filter[i][1];
         i_tradesPerName = isPositionOpen(m_myMagicNumber[i],m_names[i],temp_tickets); 
         for(int k=0; k<i_tradesPerName; k++) {                                                       // check if trades open
   		   m_ticket[i][k] = temp_tickets[k];
   		   if (readTradeComment(m_ticket[i][k],m_names[i],temp_sequence)) {
   		      //THIS PROCESS WILL OVERWRITE ANY EXTERNALLY MODIFIED SLOW FILTERS, WARP, SL and TP - THEY WILL NEED TO BE RESET EXTERNALLY AGAIN
         		for (int j=0;j<3;j++) { m_sequence[i][j] = temp_sequence[j]; }
               m_slowFilterGap[i] = NormalizeDouble(m_barTSAvg[i] * f_barSizePortion, (int)MarketInfo(m_names[i],MODE_DIGITS));  // quarter the bar size: lower SF=SF-m_slowFilterGap, upper SF=SF+m_slowFilterGap
         		Alert("ticket:",m_ticket[i][k]," ",m_names[i]," ",m_sequence[i][0]," ",m_sequence[i][1]," ",m_sequence[i][2],",",m_sequence[i][3],",",m_sequence[i][4]);
         		StringAdd(s_namesOpen,m_names[i]);
               StringAdd(s_namesOpen,"_");
         		m_bollingerDeviationInPips[i] = NormalizeDouble((1/MarketInfo(m_names[i],MODE_POINT)) * MathMax(MathAbs(OrderOpenPrice()-OrderStopLoss()),MathAbs(OrderOpenPrice()-OrderTakeProfit())),0); 
   		   }
   		   else { PrintFormat("Cannot read open trade comment %s",m_names[i]); }
         }
         m_tradesNumber[i] = (int)MathMax(1,i_tradesPerName);  //
      }
      else {
         temp = StringSplit(arr_sequence[i],u_sep,m_rows);
         m_tradesNumber[i] = StrToInteger(m_rows[1]);
         for(int k=0; k<7; k++) { m_sequence[i][k] = StringToDouble(m_rows[k+2]); }
         m_bollingerDeviationInPips[i] = StringToDouble(m_rows[9]);
         m_slowFilterGap[i] = StringToDouble(m_rows[10]);
         temp = StringSplit(arr_ticket[i],u_sep,m_rows);
         for(int k=0; k<TRADESPERNAMEMAX; k++) {
            m_ticket[i][k] = StrToInteger(m_rows[k+1]);
            if (m_ticket[i][0]>0 && k==0) { Alert("ticket:",m_ticket[i][0]," ",m_names[i]," ",m_sequence[i][0]," ",m_sequence[i][1]," ",m_sequence[i][2]); }
         }
         if (m_ticket[i][0]>0) {
            StringAdd(s_namesOpen,m_names[i]);
            StringAdd(s_namesOpen,"_");
         }
         // see what it read from the files:
         if (b_verbose) { Alert(m_names[i],",",m_tradesNumber[i],",",m_sequence[i][0],",",m_sequence[i][1],",",m_sequence[i][2],",",
                                 m_sequence[i][3],",",m_sequence[i][4],",",m_sequence[i][5],",",m_sequence[i][6],",",
                                 m_bollingerDeviationInPips[i],",",m_slowFilterGap[i],",",m_ticket[i][0],",",m_ticket[i][1]);
         }
      }
      if (FileIsExist(s_cumLossesFileName,0)) {
         temp = StringSplit(arr_volLosses[i],u_sep,m_rows);
         m_cumLosses[i] = StringToDouble(m_rows[1]);
      }
   }
   if (StringCompare(s_namesRemoved,"")!=0) { Alert("Names removed: ",s_namesRemoved); }
   if (StringCompare(s_namesOpen,"")!=0) { Alert("Tickets open: ",s_namesOpen); }
   
   // initialize m_accountCcyFactors
   if (AccountCompany()=="ThinkMarkets.com") { if (IsDemo()) { s_symbolAppendix = "pro"; } else { s_symbolAppendix = "x"; } }      // "TF Global Markets (Aust) Pty Ltd"
   else if (AccountCompany()=="UOB") { s_symbolAppendix = "#"; }
   else if (AccountCompany()=="Admiral Markets") { s_symbolAppendix = ""; }
   else { s_symbolAppendix = ""; }
   for(int i=0; i<i_namesNumber; i++) {
      m_accountCcyFactors[i] = accCcyFactor(m_names[i],s_symbolAppendix);
      if (b_verbose) { Alert("acc factor for: ",m_names[i]," is ",m_accountCcyFactors[i]); }
   }
   
   // Setting the Global variables
   GlobalVariableSet("gv_productMagicNumber",-1);
   GlobalVariableSet("gv_slowFilter",0);
   GlobalVariableSet("gv_fastFilter",-1);
   GlobalVariableSet("gv_creditAmount",0.0);
   if (GlobalVariableCheck("gv_creditBalance")) { f_creditBalance = GlobalVariableGet("gv_creditBalance"); }
   else { GlobalVariableSet("gv_creditBalance",0.0); }
   GlobalVariableSet("gv_createSnapshotForStrategy",-1);
   GlobalVariableSet("gv_slowFilterGap",-1); // Actual value not pips, this is defined as the distance from the central SF to lower or upper.
   GlobalVariableSet("gv_bollingerDevInPips",0);
   GlobalVariableSet("gv_tradesNumber",1);
   GlobalVariableSet("gv_resetSequence",0);
   GlobalVariableSet("gv_newSequenceForProduct",-1);
   
   Alert ("Function init() triggered at start for ",Symbol());// Alert
   if (IsDemo() == false) { Alert("THIS IS A REAL RUN"); } else { Alert("THIS IS DEMO RUN"); }
   Alert("This run is for strategy #",i_stratMagicNumber," using mode:",bollinger_mode," and file: ",EnumToString(inputFilenameIndex)+".txt on: ",AccountCompany());
   
   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   Alert ("Function deinit() triggered at exit for ",Symbol());// Alert
   
   // write to files
   string const s_sequenceFileName = StringConcatenate("sequence_",IntegerToString(i_stratMagicNumber),".txt");
   string const s_ticketFileName = StringConcatenate("ticket_",IntegerToString(i_stratMagicNumber),".txt");
   string const s_cumLossesFileName = StringConcatenate("cumLosses_",IntegerToString(i_stratMagicNumber),".txt");
   writeOutputToFile(s_sequenceFileName,s_ticketFileName,s_cumLossesFileName);
   
   Alert("The total cumulative PnL for strategy ",i_stratMagicNumber," is ",cumulativePnL());
   
   // TIMER KILL
   EventKillTimer();
   
   return;
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTimer()
  {

// VARIABLE DECLARATIONS /////////////////////////////////////////////////////////////////////////////////////////////////////////
   int ticket=0,price,i_ticketSum=0;
   uint tick=0;
   bool b_transition=false,b_tradeClosedBySL=false,res,b_pending=false,b_multiPositionOpen=false,b_aroundNewBar=false,b_checkEveryXMinute=false;
   double SL,TP,BID,ASK,f_fastFilterPrev=0.0,f_fastFilter=0.0,f_lotUnsplit=0,f_bollingerBandPrev = 0.0,f_bollingerBand = 0.0,temp_fastFF=0.0,temp_slowFF=0.0,temp_pnlSum=0.0;
   string s_comment,s_tradeFlag,s_adjFlag="";
   int m_signal[]; // 0:lower, 1:upper crossing of slow filter
   bool m_isPositionOpen[][TRADESPERNAMEMAX];
   bool m_isPositionPending[][TRADESPERNAMEMAX];
   int m_positionDirection[][TRADESPERNAMEMAX];
   int m_lastTicketOpenTime[][TRADESPERNAMEMAX];
   bool m_close[][TRADESPERNAMEMAX];
   int m_open[][TRADESPERNAMEMAX];
   bool m_appliedCreditFlag[],m_appliedPenaltyFlag[];
   double m_loss[];
   double m_slowFilter[];
   double m_fastFilterFreq[];
   double temp_sequence[8]={0,0,0,0,0,0,0,0};
   double m_lots[][TRADESPERNAMEMAX];
   double temp_pnl[TRADESPERNAMEMAX] = {0,0};
   double temp_T[TRADESPERNAMEMAX] = {0,0};
   string const s_accountingFileName = StringConcatenate("accounting_",IntegerToString(AccountNumber()),"_",IntegerToString(i_stratMagicNumber),".txt");
   
   // RUN FLAGS
   if (timeFrame == 5) { b_aroundNewBar = true; }  // 5 min before bar end and 5 min after: TRUE, works for H1 and H4
   else { b_aroundNewBar = (int)MathRound(MathMod(Minute() + Hour()*60,timeFrame))>timeFrame-5 || (int)MathRound(MathMod(Minute() + Hour()*60,timeFrame))<5; }
   bool const b_orderTotalChanged = !(i_ordersTotal == OrdersTotal());
   i_ordersTotal = OrdersTotal();
   if (timeFrame == 5) { b_checkEveryXMinute = true; }
   else { b_checkEveryXMinute = (Minute() == 10) || (Minute() == 20) || (Minute() == 30) || (Minute() == 40) || (Minute() == 50); }
   
// PRELIMINARY PROCESSING ///////////////////////////////////////////////////////////////////////////////////////////////////////////
   ArrayResize(m_signal,i_namesNumber,0);
   ArrayResize(m_isPositionOpen,i_namesNumber,0);
   ArrayResize(m_isPositionPending,i_namesNumber,0);
   ArrayResize(m_positionDirection,i_namesNumber,0);
   ArrayResize(m_lastTicketOpenTime,i_namesNumber,0);
   ArrayResize(m_slowFilter,i_namesNumber,0);
   ArrayResize(m_fastFilterFreq,i_namesNumber,0);
   ArrayResize(m_close,i_namesNumber,0);
   ArrayResize(m_open,i_namesNumber,0);
   ArrayResize(m_appliedCreditFlag,i_namesNumber,0);
   ArrayResize(m_appliedPenaltyFlag,i_namesNumber,0);
   ArrayResize(m_loss,i_namesNumber,0);
   ArrayResize(m_lots,i_namesNumber,0);
   ArrayInitialize(m_signal,0);
   ArrayInitialize(m_isPositionOpen,false);
   ArrayInitialize(m_isPositionPending,false);
   ArrayInitialize(m_positionDirection,0);
   ArrayInitialize(m_lastTicketOpenTime,-1);
   ArrayInitialize(m_slowFilter,0);
   ArrayInitialize(m_fastFilterFreq,0);
   ArrayInitialize(m_close,false);
   ArrayInitialize(m_open,0);
   ArrayInitialize(m_appliedCreditFlag,false);
   ArrayInitialize(m_appliedPenaltyFlag,false);
   ArrayInitialize(m_loss,0);
   ArrayInitialize(m_lots,0.0);
     
// KEEP ACCOUNTS ONCE PER DAY ///////////////////////////////////////////////////////////////////////////////////////
if (Hour()==21 && Minute()>55) { 
   if (b_accountingWriteDone==false) {
      b_accountingWriteDone = writeToAccountingFile(s_accountingFileName); 
   }
}
else if (Hour()!=21 && b_accountingWriteDone) { 
   b_accountingWriteDone = false; 
}
else { /** do nothing **/ }

// PROVIDE A RECAP EVERY HOUR ON THE 30TH MINUTE ////////////////////////////////////////////////////////////////////
if (Minute()==30 && Seconds()<15) {
	for(int i=0; i<i_namesNumber; i++) {
		if (m_sequence[i][0]>0) {
			Alert("Scheduled Recap: The slow filter for ",m_names[i],"(",(int)NormalizeDouble(m_myMagicNumber[i],0),") is ",NormalizeDouble(m_sequence[i][0],(int)MarketInfo(m_names[i],MODE_DIGITS)),
				  " with lower: ",NormalizeDouble(m_sequence[i][0]-m_slowFilterGap[i],(int)MarketInfo(m_names[i],MODE_DIGITS)),
				  " , upper: ",NormalizeDouble(m_sequence[i][0]+m_slowFilterGap[i],(int)MarketInfo(m_names[i],MODE_DIGITS)),
				  ", gap: ",NormalizeDouble(m_slowFilterGap[i],(int)MarketInfo(m_names[i],MODE_DIGITS)),
				  " Bollinger deviation: ",(int)NormalizeDouble(m_bollingerDeviationInPips[i],0),
				  " FF: ",(int)NormalizeDouble(m_sequence[i][6],0)," and #:",m_tradesNumber[i]);
		}
	}
	Alert(Day(),"-",Month(),"-",Year()," ",Hour(),":30 Scheduled Recap:");
}

// UPDATE STATUS/////////////////////////////////////////////////////////////////////////////////////////////////////
// Make sure rest of ontimer() does not run continuously when not needed
if (b_aroundNewBar || b_pendingGlobal || b_orderTotalChanged || b_checkEveryXMinute || b_openManualSequence) {
for(int i=0; i<i_namesNumber; i++) {
   if (m_tradeFlag[i]==true) {
      for(int k=0; k<TRADESPERNAMEMAX; k++) {   // keep TRADESPERNAMEMAX: we make sure that if TN is decremented before main is closed, other trades will still be accounted for
      	if (m_ticket[i][k]>0) {
			   res = OrderSelect(m_ticket[i][k],SELECT_BY_TICKET);
   			if (res) {
   				if (OrderCloseTime()>0) {			// if closed
   					if (readTradeComment(m_ticket[i][k],m_names[i],temp_sequence)) {
   						if (k==1) { b_tradeClosedBySL = (temp_sequence[6]>0.5) ? true : false; }
   						temp_pnl[k] = temp_sequence[5];
   						m_isPositionOpen[i][k]=false;
   						m_isPositionPending[i][k] = false;
   						m_positionDirection[i][k] = 0;
   					}
   				}
   				else {
   					if (OrderType()==OP_BUY) { 
   						m_isPositionOpen[i][k]=true;
   						m_isPositionPending[i][k] = false;
   						m_lastTicketOpenTime[i][k] = iBarShift(m_names[i],timeFrame,OrderOpenTime(),true);
   						m_positionDirection[i][k] = 1; }
   					else if (OrderType()==OP_SELL) { 
   						m_isPositionOpen[i][k]=true;
   						m_isPositionPending[i][k] = false;
   						m_lastTicketOpenTime[i][k] = iBarShift(m_names[i],timeFrame,OrderOpenTime(),true);
   						m_positionDirection[i][k] = -1; }
   					else if (OrderType()==OP_SELLSTOP || OrderType()==OP_SELLLIMIT) { 								// pending
   						m_isPositionOpen[i][k]=false;
   						m_isPositionPending[i][k] = true; 
   						m_positionDirection[i][k] = -1; }
   					else if (OrderType()==OP_BUYSTOP || OrderType()==OP_BUYLIMIT) { 								// pending
   						m_isPositionOpen[i][k]=false;
   						m_isPositionPending[i][k] = true; 
   						m_positionDirection[i][k] = 1; 
   					}
   				}
   			}
   			else { Alert("Failed to select trade: ",m_ticket[i][k]); }
   			b_multiPositionOpen = b_multiPositionOpen || (m_isPositionOpen[i][k] || m_isPositionPending[i][k]);
   			i_ticketSum = i_ticketSum + m_ticket[i][k];
   			b_pending = b_pending || m_isPositionPending[i][k]; // this is checking across all trades and names
		   }
	   }
	   if (!b_multiPositionOpen && i_ticketSum>0.5) {    // order is closed if no open positions but ticket numbers not yet reset
		   for(int k=0; k<TRADESPERNAMEMAX; k++) { temp_pnlSum = temp_pnlSum + temp_pnl[k]; }
		   if ((m_sequence[i][1]+temp_pnlSum)>=0.01) {	//ie trade sequence closed positive/negative by one cent or penny
				m_sequence[i][0] = -1;
				for(int k=1; k<3; k++) { m_sequence[i][k] = 0; }
				m_sequence[i][3] = f_percWarp;
				m_sequence[i][4] = f_percSL;
				m_sequence[i][5] = f_percTP;
				m_sequence[i][6] = m_filter[i][1];    // FF freq
				m_slowFilterGap[i] = 0.0;
				m_creditAmount[i] = 0.0;
				m_bollingerDeviationInPips[i] = 0;
				m_tradesNumber[i] = 1;
			}
			else {
			   // dont copy over slow filter because it may have been modified externally
			   m_sequence[i][1] = m_sequence[i][1] + temp_pnlSum;
			}
			for(int k=0; k<TRADESPERNAMEMAX; k++) { // if multi position closed reset all tickets, reset all columns and update cumulative pnl
			   m_ticket[i][k] = 0; 
			   m_cumLosses[i] = m_cumLosses[i] + temp_pnl[k];
			} 
		}
   	b_tradeClosedBySL = false;
   	for(int k=0; k<TRADESPERNAMEMAX; k++) { temp_pnl[k] = 0.0; }
   	temp_pnlSum = 0.0;
   	b_multiPositionOpen = false;
   }
}
b_pendingGlobal = b_pending;
}

/////////////// GLOBAL VARIABLES ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
f_creditBalance = GlobalVariableGet("gv_creditBalance");
if ((int)MathFloor(GlobalVariableGet("gv_productMagicNumber")/100)==i_stratMagicNumber) {
	int temp_i = (int)GlobalVariableGet("gv_productMagicNumber") - i_stratMagicNumber*100 - 1;
	// SETTING EXTERNALLY THE FAST FILTER VALUE USING GLOBAL VARIABLES /////////////////////////////////////
	if (GlobalVariableGet("gv_fastFilter")>0.00001) { 
	   m_sequence[temp_i][6] = GlobalVariableGet("gv_fastFilter");
	   GlobalVariableSet("gv_fastFilter",-1); 
	}
	// GIVING CREDIT TO STRUGGLING SEQUENCE BY PENALISING OTHERS ///////////////////////////////////////
	if (MathAbs(GlobalVariableGet("gv_creditAmount"))>0.99) { 
	   m_creditAmount[temp_i] = GlobalVariableGet("gv_creditAmount");
	   Alert("Credit Amount ",(int)NormalizeDouble(m_creditAmount[temp_i],0)," for ",m_names[temp_i],"(",(int)NormalizeDouble(GlobalVariableGet("gv_productMagicNumber"),0),") has been credited successfully.");
	   GlobalVariableSet("gv_creditAmount",0);
	}
	// UPDATE TRADE NUMBER TO SPLIT A SEQUENCE ///////////////////////////////////////
	if (GlobalVariableGet("gv_tradesNumber")>1.5) { 
	   m_tradesNumber[temp_i] = (int)GlobalVariableGet("gv_tradesNumber");
	   Alert("The trades number for ",m_names[temp_i],"(",(int)NormalizeDouble(GlobalVariableGet("gv_productMagicNumber"),0),") was changed to ",m_tradesNumber[temp_i]);
	   GlobalVariableSet("gv_tradesNumber",1);
	}
	// SETTING EXTERNALLY THE SLOW FILTER VALUE USING GLOBAL VARIABLES /////////////////////////////////////
	if (GlobalVariableGet("gv_slowFilter")>0.5 || GlobalVariableGet("gv_slowFilter")<-0.5) { 
	   m_sequence[temp_i][0] = GlobalVariableGet("gv_slowFilter");
		GlobalVariableSet("gv_slowFilter",0);
	}
	// SETTING EXTERNALLY THE SLOW FILTER GAP VALUE USING GLOBAL VARIABLES /////////////////////////////////////
	if (GlobalVariableGet("gv_slowFilterGap")>-0.0001) { 
	   m_slowFilterGap[temp_i] = GlobalVariableGet("gv_slowFilterGap");
		GlobalVariableSet("gv_slowFilterGap",-1);
	}
	// SETTING THE BOLLINGER DEVIATION EXTERNALLY ////////////////////////////////////////////////////////////
	if (MathAbs(GlobalVariableGet("gv_bollingerDevInPips"))>0.99) { 
	   m_bollingerDeviationInPips[temp_i] = GlobalVariableGet("gv_bollingerDevInPips");
	   Alert("The bollinger deviation for ",m_names[temp_i],"(",NormalizeDouble(GlobalVariableGet("gv_productMagicNumber"),0),
	   ") was changed to ",(int)NormalizeDouble(m_bollingerDeviationInPips[temp_i],0),
	   " with the original being: ",(int)NormalizeDouble(f_percAvBandSeparation*m_bandsTSAvg[temp_i],0)); 
	   GlobalVariableSet("gv_bollingerDevInPips",0);
	}
	// RESET SEQUENCE /////////////////////////////////////
	if (GlobalVariableGet("gv_resetSequence")>0.5) { 
	   m_sequence[temp_i][0] = -1;
		for(int k=1; k<3; k++) { m_sequence[temp_i][k] = 0; }
		m_sequence[temp_i][3] = f_percWarp;
		m_sequence[temp_i][4] = f_percSL;
		m_sequence[temp_i][5] = f_percTP;
		m_sequence[temp_i][6] = m_filter[temp_i][1];    // FF freq
		m_slowFilterGap[temp_i] = 0.0;
		m_bollingerDeviationInPips[temp_i] = 0;
		m_tradesNumber[temp_i] = 1;
		Alert("The sequence for ",m_names[temp_i],"(",(int)NormalizeDouble(GlobalVariableGet("gv_productMagicNumber"),0),") was reset.");
	   GlobalVariableSet("gv_resetSequence",0); 
	}
	// recap alert
	Alert("Recap: The slow filter for ",m_names[temp_i],"(",(int)NormalizeDouble(GlobalVariableGet("gv_productMagicNumber"),0),") is ",NormalizeDouble(m_sequence[temp_i][0],(int)MarketInfo(m_names[temp_i],MODE_DIGITS)),
	      " with lower: ",NormalizeDouble(m_sequence[temp_i][0]-m_slowFilterGap[temp_i],(int)MarketInfo(m_names[temp_i],MODE_DIGITS)),
	      " , upper: ",NormalizeDouble(m_sequence[temp_i][0]+m_slowFilterGap[temp_i],(int)MarketInfo(m_names[temp_i],MODE_DIGITS)),
	      ", gap: ",NormalizeDouble(m_slowFilterGap[temp_i],(int)MarketInfo(m_names[temp_i],MODE_DIGITS)),
	      " Bollinger deviation: ",(int)NormalizeDouble(m_bollingerDeviationInPips[temp_i],0),
	      " FF: ",(int)NormalizeDouble(m_sequence[temp_i][6],0)," and #:",m_tradesNumber[temp_i]);
	// resetting
   GlobalVariableSet("gv_productMagicNumber",-1);
}
// GET A SNAPSHOT
if ((int)GlobalVariableGet("gv_createSnapshotForStrategy") == i_stratMagicNumber) {			// only enter loop if 
	string const s_sequenceFileName = StringConcatenate("sequence_",IntegerToString(i_stratMagicNumber),"_snapshot",".txt");
   string const s_ticketFileName = StringConcatenate("ticket_",IntegerToString(i_stratMagicNumber),"_snapshot",".txt");
   string const s_cumLossesFileName = StringConcatenate("cumLosses_",IntegerToString(i_stratMagicNumber),"_snapshot",".txt");
   res=writeOutputToFile(s_sequenceFileName,s_ticketFileName,s_cumLossesFileName); 
   if (res) { Alert("Snapshot has been created successfully."); }
   for(int i=0; i<i_namesNumber; i++) { 
      if (m_sequence[i][0]>0) { Alert("The sequence for ",m_names[i]," is open with loss: ",-m_sequence[i][1]); } 
   }
	GlobalVariableSet("gv_createSnapshotForStrategy",-1);	// reset
}
// START NEW SEQUENCE
if ((int)MathFloor(GlobalVariableGet("gv_newSequenceForProduct")/100)==i_stratMagicNumber) {
	int temp_i = (int)GlobalVariableGet("gv_newSequenceForProduct") - i_stratMagicNumber*100 - 1;
   if (m_sequence[temp_i][0]>0) { Alert("A sequence for ",m_names[temp_i],"(",(int)NormalizeDouble(GlobalVariableGet("gv_productMagicNumber"),0),") is already open."); }
   else {   // open new sequence, first check that all inputs are provided
      if (GlobalVariableGet("gv_slowFilter")>0) {
         m_sequence[temp_i][0] = GlobalVariableGet("gv_slowFilter");
         m_sequence[temp_i][1] = -1 * MathAbs(GlobalVariableGet("gv_creditAmount"));
		   i_openSequenceForProduct = temp_i;
		   b_openManualSequence = true;
		   Alert("A sequence for ",m_names[temp_i],"(",(int)NormalizeDouble(GlobalVariableGet("gv_newSequenceForProduct"),0),") will start with slow filter ",
		            GlobalVariableGet("gv_slowFilter")," and loss ",-1 * MathAbs(GlobalVariableGet("gv_creditAmount")));
      }
      else { 
         Alert("Not all parameters have been provided to open new sequence for ",m_names[temp_i],"(",(int)NormalizeDouble(GlobalVariableGet("gv_productMagicNumber"),0),").");
      }
   }
   // resetting
   GlobalVariableSet("gv_newSequenceForProduct",-1);
   GlobalVariableSet("gv_creditAmount",0.0);
   GlobalVariableSet("gv_slowFilter",0); 
}

// Make sure rest of ontimer() does not run continuously when not needed
   if (b_aroundNewBar || b_pendingGlobal || b_openManualSequence) {
  
// INDICATOR BUFFERS ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      for(int i=0; i<i_namesNumber; i++) {
      if (m_tradeFlag[i]==true) {
         
		if (m_sequence[i][0]<0 || (m_sequence[i][2]<1.5 && iBars(m_names[i],timeFrame)==m_lastTicketOpenTime[i][0])) {	// no sequence or new sequence opened this bar                      // SF
			// This is to deal with the special case of opening new sequence. In the first bar, we should always be in the "if" part of the loop.
			f_fastFilter = iCustom(m_names[i],0,"petousis_decycler",m_filter[i][1],filter_history,1,1);   // FF fast value
			f_fastFilterPrev = iCustom(m_names[i],0,"petousis_decycler",m_filter[i][1],filter_history,1,2);
			f_bollingerBand = MathMax(iBands(m_names[i],timeFrame,(int)m_filter[i][0],bollinger_deviations,0,0,bollinger_mode,1+bollinger_delay),
								iBands(m_names[i],timeFrame,(int)m_filter[i][0],bollinger_deviations,0,0,MODE_MAIN,1+bollinger_delay) + f_minBollingerBandRatio*m_bandsTSAvg[i]*MarketInfo(m_names[i],MODE_POINT));
			f_bollingerBandPrev = MathMin(iBands(m_names[i],timeFrame,(int)m_filter[i][0],bollinger_deviations,0,0,bollinger_mode,2+bollinger_delay),
								iBands(m_names[i],timeFrame,(int)m_filter[i][0],bollinger_deviations,0,0,MODE_MAIN,2+bollinger_delay) - f_minBollingerBandRatio*m_bandsTSAvg[i]*MarketInfo(m_names[i],MODE_POINT)); 
			temp_T[0] = (f_fastFilter - f_bollingerBand)*(f_fastFilterPrev - f_bollingerBandPrev);
			temp_T[1] = temp_T[0];
		}
		else {		// existing sequence
			f_bollingerBand = m_sequence[i][0];
			f_bollingerBandPrev = f_bollingerBand;
			if (m_sequence[i][2]<2) {
				f_fastFilter = iCustom(m_names[i],0,"petousis_decycler",m_filter[i][1],filter_history,1,1);   
				f_fastFilterPrev = iCustom(m_names[i],0,"petousis_decycler",m_filter[i][1],filter_history,1,2);	
			}
			else if (m_sequence[i][2]>=2  && (int)m_sequence[i][6]==(int)m_filter[i][1]) {
				temp_fastFF = iCustom(m_names[i],0,"petousis_decycler",m_filter[i][1],filter_history,1,1); 
				temp_slowFF = iCustom(m_names[i],0,"petousis_decycler",m_filter[i][2],filter_history,1,1);
				b_transition = (temp_fastFF<f_bollingerBand-m_slowFilterGap[i] && temp_slowFF<f_bollingerBand-m_slowFilterGap[i]) ||
				(temp_fastFF>f_bollingerBand+m_slowFilterGap[i] && temp_slowFF>f_bollingerBand+m_slowFilterGap[i]) ||
				(temp_fastFF>f_bollingerBand-m_slowFilterGap[i] && temp_fastFF<f_bollingerBand+m_slowFilterGap[i] && temp_slowFF>f_bollingerBand-m_slowFilterGap[i] && temp_slowFF<f_bollingerBand+m_slowFilterGap[i]);
				if (b_transition) { //transition if current slow FF is in the same region as current fast FF
					f_fastFilter = temp_slowFF;   
					f_fastFilterPrev = iCustom(m_names[i],0,"petousis_decycler",m_filter[i][2],filter_history,1,2);
					m_sequence[i][6] = m_filter[i][2];
				}
				else { // dont transition
					f_fastFilter = temp_fastFF;   
					f_fastFilterPrev = iCustom(m_names[i],0,"petousis_decycler",m_filter[i][1],filter_history,1,2);
				}
			}
			else {
				f_fastFilter = iCustom(m_names[i],0,"petousis_decycler",m_filter[i][2],filter_history,1,1);   
				f_fastFilterPrev = iCustom(m_names[i],0,"petousis_decycler",m_filter[i][2],filter_history,1,2);
			}
			temp_T[0] = (f_fastFilter - (f_bollingerBand-m_slowFilterGap[i]))*(f_fastFilterPrev - (f_bollingerBandPrev-m_slowFilterGap[i]));
			temp_T[1] = (f_fastFilter - (f_bollingerBand+m_slowFilterGap[i]))*(f_fastFilterPrev - (f_bollingerBandPrev+m_slowFilterGap[i]));
		}
	         
          if (temp_T[0] < 0 || temp_T[1] < 0) {
            if (m_sequence[i][0]<0) {         // either new sequence or manually set (-1) mid-sequence, so update the pips
	            m_bollingerDeviationInPips[i] = NormalizeDouble(f_percAvBandSeparation*m_bandsTSAvg[i],0);
	            m_slowFilterGap[i] = NormalizeDouble(m_barTSAvg[i] * f_barSizePortion, (int)MarketInfo(m_names[i],MODE_DIGITS));  // quarter the bar size: lower SF=SF-m_slowFilterGap, upper SF=SF+m_slowFilterGap
	            if (f_fastFilter>f_bollingerBand) { 
                  // when on free moving slow filter only enter buy on upper and sell on lower.
                  if (bollinger_mode==1) { m_signal[i] = 2; } else { m_signal[i] = 0; }
                  // Use fast filter to set slow filter level if 1) new sequence or 2) change larger than f_adjustLevel
                  m_slowFilter[i] = MathMax(f_bollingerBand,f_fastFilter-f_adjustLevel*m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT));
               }
               else if (f_fastFilter<f_bollingerBand) { 
                  // when on free moving slow filter only enter buy on upper and sell on lower.
                  if (bollinger_mode==2) { m_signal[i] = -2; } else { m_signal[i] = 0; }
                  // Use fast filter to set slow filter level if 1) new sequence or 2) change larger than f_adjustLevel
                  m_slowFilter[i] = MathMin(f_bollingerBand,f_fastFilter+f_adjustLevel*m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT));
               }
            }
            else {
               if (f_fastFilter>f_bollingerBand+m_slowFilterGap[i]) { 
                  m_signal[i] = 2;
                  // Use fast filter to set slow filter level if 1) new sequence or 2) change larger than f_adjustLevel
                  if (m_sequence[i][0]>0 && (MathAbs(m_sequence[i][0]-f_fastFilter)>f_adjustLevel*m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT))) { 
            			m_slowFilter[i] = f_fastFilter - MarketInfo(m_names[i],MODE_POINT); 
            		}
   		         else { m_slowFilter[i] = m_sequence[i][0]; }
               }
               else if (f_fastFilter>f_bollingerBand-m_slowFilterGap[i] && f_fastFilter<f_bollingerBand+m_slowFilterGap[i] && f_fastFilterPrev<f_bollingerBand-m_slowFilterGap[i]) {
                  m_signal[i] = 1;
               }
               else if (f_fastFilter>f_bollingerBand-m_slowFilterGap[i] && f_fastFilter<f_bollingerBand+m_slowFilterGap[i] && f_fastFilterPrev>f_bollingerBand+m_slowFilterGap[i]) {
                  m_signal[i] = -1;
               }
   	         else if (f_fastFilter<f_bollingerBand-m_slowFilterGap[i]) { 
                  m_signal[i] = -2;
                  // Use fast filter to set slow filter level if 1) new sequence or 2) change larger than f_adjustLevel
                  if (m_sequence[i][0]>0 && (MathAbs(m_sequence[i][0]-f_fastFilter)>f_adjustLevel*m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT))) { 
            			m_slowFilter[i] = f_fastFilter + MarketInfo(m_names[i],MODE_POINT); 
            		}
   		         else { m_slowFilter[i] = m_sequence[i][0]; }
               }
               else { m_signal[i] = 0; }
            }
		   }
		else if (i==i_openSequenceForProduct) {
		   f_fastFilter = iCustom(m_names[i],0,"petousis_decycler",m_filter[i][1],filter_history,1,1);   
			m_bollingerDeviationInPips[i] = NormalizeDouble(f_percAvBandSeparation*m_bandsTSAvg[i],0);
	      m_slowFilterGap[i] = NormalizeDouble(m_barTSAvg[i] * f_barSizePortion, (int)MarketInfo(m_names[i],MODE_DIGITS));  // quarter the bar size: lower SF=SF-m_slowFilterGap, upper SF=SF+m_slowFilterGap
			m_slowFilter[i] = m_sequence[i][0];
			if (f_fastFilter > m_slowFilter[i]) { m_signal[i] = 2; Alert("Buy signal sent."); }
			else if (f_fastFilter < m_slowFilter[i]) { m_signal[i] = -2; Alert("Sell signal sent."); }
			else { m_signal[i] = 0; Alert("Fast Filter has exact same value as the Slow Filter - cannot decide direction."); }
		}
        else { m_signal[i] = 0; }
      }
      }
      
      
// INTERPRET SIGNAL /////////////////////////////////////////////////////////////////////////////////////////////////////////
for(int i=0; i<i_namesNumber; i++) {
   if (m_tradeFlag[i]==true && m_signal[i]!=0) {
      for(int k=0; k<m_tradesNumber[i]; k++) {
         if (m_signal[i]>0 && m_positionDirection[i][k]<0 && iBars(m_names[i],timeFrame)>m_lastTicketOpenTime[i][0]) { m_close[i][k]=true; }
         else if (m_signal[i]>1 && m_positionDirection[i][k]==0 && iBars(m_names[i],timeFrame)>m_lastTicketOpenTime[i][0]) { m_open[i][k]=1; }
         else if (m_signal[i]<0 && m_positionDirection[i][k]>0 && iBars(m_names[i],timeFrame)>m_lastTicketOpenTime[i][0]) { m_close[i][k]=true; }
         else if (m_signal[i]<-1 && m_positionDirection[i][k]==0 && iBars(m_names[i],timeFrame)>m_lastTicketOpenTime[i][0]) { m_open[i][k]=-1; }
         else { }// do nothing
      }   
   }
}
   
// CLOSING ORDERS //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 
 for(int i=0; i<i_namesNumber; i++) {
 if (m_tradeFlag[i]==true) {
      for(int k=0; k<m_tradesNumber[i]; k++) {
         if (m_close[i][k]) {
               RefreshRates();
               Alert("Attempt to close ",m_ticket[i][k]); 
      			res = OrderSelect(m_ticket[i][k],SELECT_BY_TICKET);
      			if(OrderType()==0) {price=MODE_BID;} else {price=MODE_ASK;}
      			if (m_isPositionPending[i][k]==true) { res = OrderDelete(m_ticket[i][k]); }
      			else { res = OrderClose(m_ticket[i][k],OrderLots(),MarketInfo(m_names[i],price),100); }         // slippage 100, so it always closes
               if (res==true) { Alert("Order closed."); }
               else { Alert("Order close failed."); }
         }
      }
  }
  }
 
 // OPENING ORDERS //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   for(int i=0; i<i_namesNumber; i++) {
   if (m_tradeFlag[i]==true) {
      for(int k=0; k<m_tradesNumber[i]; k++) {
         if (m_isPositionPending[i][k]==true && m_open[i][k]==0) {     // if pending order exists -> modify pending order
          		RefreshRates(); 
         		if (m_positionDirection[i][k]==1) { 
         			ASK = MarketInfo(m_names[i],MODE_ASK)-MarketInfo(m_names[i],MODE_STOPLEVEL)*MarketInfo(m_names[i],MODE_POINT);
					SL=NormalizeDouble(ASK - m_sequence[i][4] * m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));
                    TP=NormalizeDouble(ASK + m_sequence[i][5] * m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));   // Calculating TP of opened
         			res = OrderModify(m_ticket[i][k],ASK,SL,TP,0); 
         		}
         		else if (m_positionDirection[i][k]==-1) { 
         			BID = MarketInfo(m_names[i],MODE_BID)+MarketInfo(m_names[i],MODE_STOPLEVEL)*MarketInfo(m_names[i],MODE_POINT);
            		SL=NormalizeDouble(BID + m_sequence[i][4]*m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));
					TP=NormalizeDouble(BID - m_sequence[i][5]*m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));   // Calculating TP of opened
         			res = OrderModify(m_ticket[i][k],BID,SL,TP,0); 
         		}
         		else { res=false; }
          		if (res) { Print("Order modified successfully:",m_names[i]); }
          		else { Alert(m_names[i],": Order modification failed with error #", GetLastError()); }
       	}
      }
      if (!(b_noNewSequence && m_sequence[i][0]<0)) {  // Send order when no new sequence flag is off 
         for(int k=0; k<m_tradesNumber[i]; k++) {
            
			if (m_open[i][k]>0 || m_open[i][k]<0) {
				// Loss per name
				if ((-m_sequence[i][1]<f_creditPenaltyThreshold && f_creditBalance>0)) { // apply penalty with credit balance
					 m_loss[i] = -m_sequence[i][1] + f_creditPenalty; 
					 m_appliedPenaltyFlag[i] = true; } 
				else if (m_creditAmount[i]>0) {		// or apply credit
					m_loss[i] = -m_sequence[i][1] - m_creditAmount[i]; 
					m_appliedCreditFlag[i] = true; }
				else { 
					m_loss[i] = -m_sequence[i][1]; 
				}
				// Lots per trade
				f_lotUnsplit = NormalizeDouble(MathMax(m_lotMin[i], MathMax(m_profitInAccCcy[i],MathAbs(m_loss[i])/m_sequence[i][3]) / m_accountCcyFactors[i] / m_bollingerDeviationInPips[i]),m_lotDigits[i]);
				if (f_lotUnsplit>MarketInfo(m_names[i],MODE_MAXLOT)) { Alert("The lots for ",m_names[i]," are above the permissible amount and will be split."); }
				if (f_lotUnsplit>TRADESPERNAMEMAX * MarketInfo(m_names[i],MODE_MAXLOT)) { Alert("The lots for ",m_names[i]," are ",TRADESPERNAMEMAX," times above the permissible amount and CANNOT be split."); }
				if (m_tradesNumber[i]>1) { m_lots[i][k] = NormalizeDouble(f_lotUnsplit / m_tradesNumber[i],m_lotDigits[i]); }
				else { m_lots[i][k] = NormalizeDouble(f_lotUnsplit,m_lotDigits[i]);  Alert(f_lotUnsplit,"_",m_lotDigits[i]); }
			}
			RefreshRates();                        // Refresh rates
			
            // OPEN BUY
            if (m_open[i][k]>0) {                                       // criterion for opening Buy
               
               // LEVELS
               ASK = MarketInfo(m_names[i],MODE_ASK)-MarketInfo(m_names[i],MODE_STOPLEVEL)*MarketInfo(m_names[i],MODE_POINT);
			   SL=NormalizeDouble(ASK - m_sequence[i][4]*m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));
               TP=NormalizeDouble(ASK + m_sequence[i][5]*m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));   // Calculating TP of opened
               
         	    // COMMENT
               if (m_sequence[i][2]>1 && MathAbs(m_sequence[i][0]-m_slowFilter[i])>MarketInfo(m_names[i],MODE_POINT)) { s_adjFlag = "A"; }	// update if last move too big
      		   else { s_adjFlag = ""; }
               switch (m_tradesNumber[i]) {
                  case 1: s_tradeFlag = ""; break;
                  default: s_tradeFlag = m_commentTradeFlag[k];
               }
               s_comment = StringConcatenate(IntegerToString(m_myMagicNumber[i]),s_tradeFlag,"_",DoubleToStr(m_slowFilter[i],(int)MarketInfo(m_names[i],MODE_DIGITS)),
												s_adjFlag,"_",DoubleToStr(-m_loss[i],2),"_",DoubleToStr(m_sequence[i][2]+(k==0),0));
               
               // ORDER
               tick = GetTickCount();
               ticket=OrderSend(m_names[i],OP_BUYLIMIT,m_lots[i][k],ASK,slippage,SL,TP,s_comment,m_myMagicNumber[i]); //Opening Buy
               Alert("It took ",GetTickCount()-tick,"msec to open this trade.");
           }
         // OPEN SELL
         if (m_open[i][k]<0) {                                       // criterion for opening Sell
            
            // LEVELS
            BID = MarketInfo(m_names[i],MODE_BID)+MarketInfo(m_names[i],MODE_STOPLEVEL)*MarketInfo(m_names[i],MODE_POINT);
			SL=NormalizeDouble(BID + m_sequence[i][4]*m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));
            TP=NormalizeDouble(BID - m_sequence[i][5]*m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));   // Calculating TP of opened
            
      	   // COMMENT
            if (m_sequence[i][2]>1 && MathAbs(m_sequence[i][0]-m_slowFilter[i])>MarketInfo(m_names[i],MODE_POINT)) { s_adjFlag = "A"; }	// update if last move too big
      		else { s_adjFlag = ""; }
            switch (m_tradesNumber[i]) {
               case 1: s_tradeFlag = ""; break;
               default: s_tradeFlag = m_commentTradeFlag[k];
            }
            s_comment = StringConcatenate(IntegerToString(m_myMagicNumber[i]),s_tradeFlag,"_",DoubleToStr(m_slowFilter[i],(int)MarketInfo(m_names[i],MODE_DIGITS)),
											s_adjFlag,"_",DoubleToStr(-m_loss[i],2),"_",DoubleToStr(m_sequence[i][2]+(k==0),0));
            
			// ORDER 
			tick = GetTickCount();
            ticket=OrderSend(m_names[i],OP_SELLLIMIT,m_lots[i][k],BID,slippage,SL,TP,s_comment,m_myMagicNumber[i]); //Opening Sell
            Alert("It took ",GetTickCount()-tick,"msec to open this trade.");
         }
         // ALERTS AND ACCOUNTiNG
         if (m_open[i][k]<0 || m_open[i][k]>0) {
            Print("OrderSend returned:",ticket," Lots: ",m_lots[i][k]); 
            if (ticket < 0)     {                 
               Alert("OrderSend failed with error #", GetLastError());
               Alert("Loss: ",-m_loss[i],". Factor: ",m_accountCcyFactors[i],". Pips: ",m_bollingerDeviationInPips[i],". SL: ",SL,". TP: ",TP);
            }
            else {				// Success :)
               if (m_open[i][k]<0) { m_sequence[i][0] = MathCeil(m_slowFilter[i]/MarketInfo(m_names[i],MODE_POINT))*MarketInfo(m_names[i],MODE_POINT); }
               else { m_sequence[i][0] = MathFloor(m_slowFilter[i]/MarketInfo(m_names[i],MODE_POINT))*MarketInfo(m_names[i],MODE_POINT); }
               if (k==0) { m_sequence[i][2] = m_sequence[i][2] + 1; }                       // increment trade number if it is the main trade                            // main
               Alert ("Opened pending order ",ticket,",Symbol:",m_names[i]," Lots:",m_lots[i][k]);
   			   m_ticket[i][k] = ticket;
         		if (m_appliedCreditFlag[i]) {
         		  	f_creditBalance = f_creditBalance + m_creditAmount[i]; 
         		  	GlobalVariableSet("gv_creditBalance",f_creditBalance);
         			m_creditAmount[i] = 0;	// reset credit amount
         			m_sequence[i][1] = -m_loss[i]; 
      		  }
      		  if (m_appliedPenaltyFlag[i]) {
      		  	if (f_creditBalance>0) {
      		  	   f_creditBalance = f_creditBalance - f_creditPenalty; 
      		  	   GlobalVariableSet("gv_creditBalance",f_creditBalance);
      		  	}
      			m_sequence[i][1] = -m_loss[i]; 
      		  }
			  if (i==i_openSequenceForProduct) { i_openSequenceForProduct = -1; b_openManualSequence=false; }		// if there is an manual open request, reset the flag after trade opens.
            }
         }
                                       
        }
        }
    }
    }
     
   return;                                      // exit start()
   }
   else { return; }
  }
  
  // FUNCTIONS  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  
  int isPositionOpen(int myMagicNumber, string symbol, int &output[])
  {
   int local_counter = 0;
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol && (OrderType()==OP_BUY || OrderType()==OP_SELL) )
        {
         output[local_counter] = OrderTicket();
         local_counter = local_counter + 1;
        }
     }
   return local_counter;
  }

  string getName(string s1, string s2)          // gives index
  {
   string temp1 = StringConcatenate(s1,s2);
   string temp2 = StringConcatenate(s2,s1);
   string const m_symbolsList[27] = {
   "AUDCAD",
   "AUDNZD",
   "AUDUSD",
   "AUDCHF",
   "AUDJPY",
   "EURGBP",
   "EURAUD",
   "EURJPY",
   "EURCAD",
   "EURCHF",
   "EURUSD",
   "GBPAUD",
   "GBPNZD",
   "GBPJPY",
   "GBPCAD",
   "GBPCHF",
   "GBPUSD",
   "NZDJPY",
   "NZDCAD",
   "NZDCHF",
   "NZDUSD",
   "CADJPY",
   "CADCHF",
   "CHFJPY",
   "USDJPY",
   "USDCAD",
   "USDCHF"
   };
   for(int name_i=0; name_i<27; name_i++) {
      if (StringCompare(temp1,StringSubstr(m_symbolsList[name_i],0,6),false)==0) { return m_symbolsList[name_i]; }
      if (StringCompare(temp2,StringSubstr(m_symbolsList[name_i],0,6),false)==0) { return m_symbolsList[name_i]; }
   }
   return "NONE";
  }
  
  int getMagicNumber(string symbol,int stratMagicNumber)
  {
   for(int i=0; i<i_namesNumber; i++) {
      if (StringCompare(symbol,m_names[i],false) == 0) { 
         return stratMagicNumber*100 + (i+1); 
      }
   }
   return 0;
  }
  
  bool writeOutputToFile(string sequenceFileName, string ticketFileName, string cumLossesFileName)
  {
      int h=FileOpen(sequenceFileName,FILE_WRITE|FILE_TXT|FILE_READ);
      if (h!=INVALID_HANDLE) {
         for(int i=0; i<i_namesNumber; i++) { 
            FileWrite(h,m_names[i],",",
						m_tradesNumber[i],",",
						m_sequence[i][0],",",
						NormalizeDouble(m_sequence[i][1],2),",",
						m_sequence[i][2],",",
						m_sequence[i][3],",",
						m_sequence[i][4],",",
						m_sequence[i][5],",",
						m_sequence[i][6],",",
						m_bollingerDeviationInPips[i],",",
						m_slowFilterGap[i]); 
         } 
         FileClose(h); 
      }
      else { Alert("fileopen ",sequenceFileName," failed, error:",GetLastError()); return false; }
      h=FileOpen(ticketFileName,FILE_WRITE|FILE_TXT|FILE_READ);
      if (h!=INVALID_HANDLE) {
         for(int i=0; i<i_namesNumber; i++) {
            FileWrite(h,m_names[i],",",m_ticket[i][0],",",m_ticket[i][1]);
         } 
         FileClose(h); 
      }
      else { Alert("fileopen ",ticketFileName," failed, error:",GetLastError()); return false; }
      h=FileOpen(cumLossesFileName,FILE_WRITE|FILE_TXT|FILE_READ);
      if (h!=INVALID_HANDLE) {
         for(int i=0; i<i_namesNumber; i++) {
            FileWrite(h,m_names[i],",",NormalizeDouble(m_cumLosses[i],2));
         } 
         FileClose(h); 
      }
      else { Alert("fileopen ",cumLossesFileName," failed, error:",GetLastError()); return false; }
      return true;
  }
  
  bool writeToAccountingFile(string accountingFileName)
  {
      int h=FileOpen(accountingFileName,FILE_WRITE|FILE_TXT|FILE_READ);
      if (h!=INVALID_HANDLE) {
         FileSeek(h,0,SEEK_END);
         FileWrite(h,Year(),"-",Month(),"-",Day(),",",NormalizeDouble(AccountBalance(),0),",",NormalizeDouble(AccountMargin(),0));
         FileClose(h); 
      }
      else { Alert("fileopen ",accountingFileName," failed, error:",GetLastError()); return false; }
      return true;
  }
  
  double cumulativePnL()
  {
      double pnl = 0;
      for(int i=0; i<i_namesNumber; i++) { 
         pnl = pnl + m_cumLosses[i];
      } 
      return pnl;
  }
  
  bool readTradeComment(int ticket,string symbol, double &output[])
  {
   string result[];
   ushort u_sep=StringGetCharacter("_",0);
   int temp;
   ArrayInitialize(output,0);
       if(OrderSelect(ticket,SELECT_BY_TICKET)) {
          temp = StringSplit(OrderComment(),u_sep,result);
          if (ArraySize(result)<4) { PrintFormat("Comment format is wrong for ",symbol); return false; }
          temp = StringFind(result[1],"A");
          if (temp<0) {
            output[0] = StrToDouble(result[1]); } //vwap
          else {
            output[0] = StrToDouble(StringSubstr(result[1],0,temp)); 
          }
          if (OrderCloseTime()>0) {
      	output[1] = StrToDouble(result[2]);   // cum loss
      	output[3] = (double)iBarShift(symbol,timeFrame,OrderCloseTime(),false); 
      	output[5] = OrderProfit() + OrderCommission() + OrderSwap(); 
      	if (StringFind(result[3],"[sl]")>0) { output[6] = 1; } else { output[6] = 0; }    // this is to know whether trade closed by SL or not
      	}
          else {
      	output[1] = StrToDouble(result[2]);   // cum loss
      	output[3] = 0.0;
      	output[5] = 0.0;
      	output[6] = 0;
          }
          output[4] = OrderTicket();
          output[7] = OrderLots();
          temp = StringFind(result[3],"[");
          if (temp<0) {
             output[2] = StrToDouble(result[3]); } // trade number
          else if (temp==1) {
             output[2] = StrToDouble(StringSubstr(result[3],0,1));
          }
          else if (temp==2) {
             output[2] = StrToDouble(StringSubstr(result[3],0,2)); }
          return true;
       }
       else  { return false; }
}
  
  double accCcyFactor(string symbol, string appendix)
  {
      // initialize m_accountCcyFactors
      /**
      This factor defines for 1lot of each product how many USD per pip:
      For 1lot USDXXX, 1pip is USD1/USDXXX 
      For 1lot USDJPY, 1pip is JPY100 so 100/USDJPY
      For 1lot XXXUSD 1pip is USD1 
      For 1lot XAUUSD 1pip is USD1 
      For 1lot WTI 1pip is USD10 so 10
      For 1lot CC1CC2, 1pip is USD1/USDCC2 
      For 1lot CC1JPY, 1pip is USD100/USDJPY 
      For 1lot CC1CC2, 1pip is USD1/CC2USD 
      Then by simply saying for Cash(USD)/#pips how many lots, we can use the formula lots=Cash(USD)/#pips/Factor
      **/
      double result=1.0;
      string const s_broker = AccountCompany();
      if (StringCompare(StringSubstr(symbol,0,3),AccountCurrency(),false)==0) {     // ACCXXX
          if (StringCompare(StringSubstr(symbol,3,3),"JPY",false)==0) {
              result = 100 / MarketInfo(symbol,MODE_BID); }
          else { result = 1.0 / MarketInfo(symbol,MODE_BID); }
      }
      else if (StringCompare(StringSubstr(symbol,3,3),AccountCurrency(),false)==0) {  // XXXACC inc XAUUSD,XAGUSD if ACC=USD
         if (StringCompare(StringSubstr(symbol,0,3),"XAG",false)==0) { result = 5.0; }
         else { result = 1.0; }
      }
      else {       // all other pairs/products inc XAUUSD,XAGUSD if ACC!=USD 
         string k = StringConcatenate(getName(StringSubstr(symbol,3,3),AccountCurrency()),appendix);
         if (StringCompare(k,"NONE",false)!=0) {
            if (StringFind(k,AccountCurrency())==0) {
	    	      if (StringFind(k,StringConcatenate(AccountCurrency(),"JPY"))>-1) { result = 100 / MarketInfo(k,MODE_BID); }
	    	      else if (StringCompare(StringSubstr(symbol,0,3),"XAG",false)==0) { result = 5 / MarketInfo(k,MODE_BID); }
		         else { result = 1.0 / MarketInfo(k,MODE_BID); }
	         }
            else if (StringFind(k,AccountCurrency())==3) { 
               if (StringCompare(StringSubstr(symbol,0,3),"XAG",false)==0) { result = MarketInfo(k,MODE_BID) / 5; }
               else { result = MarketInfo(k,MODE_BID); } 
            }
         } 
         else {      // non-currency products (some VS USD)
            k = StringConcatenate(getName("USD",AccountCurrency()),appendix);
            if (StringCompare(s_broker,"TF Global Markets (Aust) Pty Ltd",false)==0) {    // ThinkMarkets
               if (StringCompare(StringSubstr(symbol,0,3),"WTI",false)==0) { result = 10.0 / MarketInfo(k,MODE_BID); }
               else if (StringCompare(StringSubstr(symbol,0,3),"BRE",false)==0) { result = 10.0 / MarketInfo(k,MODE_BID); }
               else if (StringCompare(StringSubstr(symbol,0,3),"SPX",false)==0) { result = 1.0 / MarketInfo(k,MODE_BID); }
               else { result = 1.0; Alert("WARNING: NO MATCHING ACC FACTOR WAS FOUND FOR SYMBOL: ",symbol); }
            }
            else if (StringCompare(s_broker,"Admiral Markets",false)==0) {            // Admiral
               if (StringCompare(StringSubstr(symbol,0,8),"[ASX200]",false)==0) { result = 0.005; }
               else if (StringCompare(StringSubstr(symbol,0,7),"[DAX30]",false)==0) { result = 0.01; }
               else if (StringCompare(StringSubstr(symbol,0,7),"[DJI30]",false)==0) { result = 0.005; }
               else if (StringCompare(StringSubstr(symbol,0,9),"[FTSE100]",false)==0) { result = 0.01; }
               else if (StringCompare(StringSubstr(symbol,0,7),"[NQ100]",false)==0) { result = 0.01 / MarketInfo(k,MODE_BID); }
               else if (StringCompare(StringSubstr(symbol,0,7),"[SP500]",false)==0) { result = 0.01 / MarketInfo(k,MODE_BID); }
               else if (StringCompare(StringSubstr(symbol,0,4),"GOLD",false)==0) { result = 1.0; }
               else if (StringCompare(StringSubstr(symbol,0,6),"SILVER",false)==0) { result = 5.0; }
               else if (StringCompare(StringSubstr(symbol,0,3),"WTI",false)==0) { result = 1.0; }
               else {result = 1.0; Alert("WARNING: NO MATCHING ACC FACTOR WAS FOUND FOR SYMBOL: ",symbol); }
            }
            else {result = 1.0; Alert("WARNING: NO MATCHING ACC FACTOR WAS FOUND FOR SYMBOL: ",symbol); }
         }
      }
      
      return result;
}
 