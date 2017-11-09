//+------------------------------------------------------------------+
//|                                       DimitrisTestChartEvent.mq4 |
//|                        Copyright 2015, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2015, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// OTMql4Py 
//#include <OTMql4/OTLibPyLog.mqh>
//#include <OTMql4/OTLibPy27.mqh>
//#include <WinUser32.mqh>

// Run in command window
//#import "shell32.dll"
//int ShellExecuteW(int hwnd,const string Operation,const string File,const string Parameters,const string Directory,int ShowCmd);
//#import

// NOTES /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/**
- ALWAYS START RUNNING ON SUNDAY EVENING BECAUSE LACK OF CONNECTION CAN CAUSE DELAYED SIGNALS TO TRADE
- ALWAYS STOP IT ON SATURDAY MORNINGS
- SL,TP SHOULD BE GIVEN IN PIPS UNLESS AUTOMATICALLY GENERATED
**/

// DEFINITIONS ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#define NAMESNUMBERMAX 50                 // this is the max number of names currently - it can be set higher if needed

// INPUTS ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//input switches
extern bool b_noNewSequence = false;
input string s_inputFileName = "TF_DEMO_H1_TRENDSTALKER.txt"; 
bool b_lockIn = true;
// Percentage of TP above which trade will always be a winning or breakeven
double const f_percWarp = 0.3;
double const f_adjustLevel = 0.1;
//bool b_trailingSL = false;
//bool b_writeToFile = false;
bool b_sendEmail=false;
// always positive
input int i_stratMagicNumber = 48; 
//input double const f_deviationPerc = 1.5;
// filter 
int const filter_history = 50;
double const bollinger_deviations = 1.5;
input int const bollinger_mode = 1;		// 1:MODE_UPPER 2:MODE_LOWER
//int i_mode = 3; // 1:VWAP 2:MA, 3:BOLLINGER
//bool filter_supersmoother = true;

// TRADE ACCOUNTING VARIABLES ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
int const slippage =10;           // in points
int const timeFrame=Period();        
int count = 0,i_namesNumber=0;
bool Work = true;             //EA will work
string const symb =Symbol();
int m_myMagicNumber[NAMESNUMBERMAX];  // Magic Numbers
double m_lots[NAMESNUMBERMAX];
double m_accountCcyFactors[NAMESNUMBERMAX];
double m_sequence[NAMESNUMBERMAX][3];     // VWAP,Cum Losses excl current,current trade number
string m_names[NAMESNUMBERMAX];
double m_bollingerDeviationInPips[];
bool m_tradeFlag[];
double m_filter[][2];      // vwap,filter freq
double m_profitInUSD[];
int m_lotDigits[];
double m_lotMin[];
int m_ticket[];
double temp_sequence[6];
double m_bandsTSAvg[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   int const i_bandsHistory = 1000;
   double f_overlap,f_low1,f_low2,f_high1,f_high2,f_scale,f_barSizeTSAvg = 0.0;
   
   // TIMER FREQUENCY - APPARENTLY NO SERVER CONTACT FOR MORE THAN 30SEC WILL CAUSE REAUTHENTICATION ADDING CONSIDERABLE DELAY, SO THEREFORE USE 15SEC INTERVAL
   if (timeFrame == 1) { EventSetTimer(10); }
   else { EventSetTimer(15); }
   //Alert(Bars,"____",iBarShift(symb,timeFrame,TimeCurrent(),true));
   
   // READ IN THE FILE
   string m_rows[8];
   ushort u_sep=StringGetCharacter(",",0);
   int temp;
   string arr[];
   int filehandle=FileOpen(s_inputFileName,FILE_READ|FILE_TXT);
   if(filehandle!=INVALID_HANDLE) {
      FileReadArray(filehandle,arr);
      FileClose(filehandle);
      Print("FileOpen OK");
   }
   else PrintFormat("Failed to open %s file, Error code = %d",s_inputFileName,GetLastError());
   i_namesNumber = ArraySize(arr);
   
   // Initialize arrays
   ArrayInitialize(m_sequence,0.0);
   ArrayInitialize(m_myMagicNumber,0);
   ArrayInitialize(m_lots,0.0);
   ArrayInitialize(m_accountCcyFactors,0.0);
   ArrayInitialize(m_bollingerDeviationInPips,0);
   ArrayInitialize(m_tradeFlag,false);
   ArrayInitialize(m_filter,0.0);
   ArrayInitialize(m_profitInUSD,0.0);
   ArrayInitialize(m_lotDigits,0.0);
   ArrayInitialize(m_lotMin,0.0);
   ArrayInitialize(m_ticket,0);
   ArrayInitialize(m_bandsTSAvg,0.0);
   
   // Resize arrays once number of products known
   ArrayResize(m_names,i_namesNumber,0);
   ArrayResize(m_sequence,i_namesNumber,0);
   ArrayResize(m_myMagicNumber,i_namesNumber,0);
   ArrayResize(m_lots,i_namesNumber,0);
   ArrayResize(m_accountCcyFactors,i_namesNumber,0);
   ArrayResize(m_bollingerDeviationInPips,i_namesNumber,0);
   ArrayResize(m_tradeFlag,i_namesNumber,0);
   ArrayResize(m_filter,i_namesNumber,0);
   ArrayResize(m_profitInUSD,i_namesNumber,0);
   ArrayResize(m_lotDigits,i_namesNumber,0);
   ArrayResize(m_lotMin,i_namesNumber,0);
   ArrayResize(m_ticket,i_namesNumber,0);
   ArrayResize(m_bandsTSAvg,i_namesNumber,0);
   for(int i=0; i<i_namesNumber; i++) {
      // m_names array
      temp = StringSplit(arr[i],u_sep,m_rows);
      if (temp == ArraySize(m_rows)) {
         m_names[i] = m_rows[0];
         if (StringCompare(m_rows[1],"Y",false)==0) {
            m_tradeFlag[i] = true;
         }
         m_profitInUSD[i] = StringToDouble(m_rows[2]);
         m_filter[i][0] = StringToDouble(m_rows[3]);
         m_filter[i][1] = StringToDouble(m_rows[4]);
      }
      else { PrintFormat("Failed to read row number %d, Number of elements read = %d instead of %d",i,temp,ArraySize(m_rows)); }
      // magic numbers
      m_myMagicNumber[i] = getMagicNumber(m_names[i],i_stratMagicNumber);
      // lot details
      m_lotDigits[i] = (int)MathMax(-MathLog10(MarketInfo(m_names[i],MODE_LOTSTEP)),0);
      if (m_lotDigits[i]<0) { Alert("Lot digits calculation is wrong for ",m_names[i]); }
      m_lotMin[i] = MarketInfo(m_names[i],MODE_MINLOT);
      // initialize m_accountCcyFactors
      m_accountCcyFactors[i] = accCcyFactor(m_names[i]);
      
      // initialize m_sequence  
      m_sequence[i][0] = -1.0;      //Initialize to -1,0,0      
      if (isPositionOpen(m_myMagicNumber[i],m_names[i])) {                                                       // check if trade open
		 m_ticket[i] = OrderTicket();
		 if (readTradeComment(m_ticket[i],m_names[i],temp_sequence)) {
			for (int j=0;j<3;j++) {
			   //THIS PROCESS WILL OVERWRITE ANY EXTERNALLY MODIFIED SLOW FILTERS - THEY WILL NEED TO BE RESET EXTERNALLY AGAIN
			   m_sequence[i][j] = temp_sequence[j];
			}
			Alert("ticket:",m_ticket[i]," ",m_names[i]," ",m_sequence[i][0]," ",m_sequence[i][1]," ",m_sequence[i][2]);
			m_bollingerDeviationInPips[i] = NormalizeDouble((1/MarketInfo(m_names[i],MODE_POINT)) * MathAbs(OrderOpenPrice()-OrderStopLoss()),0); }
		 else { PrintFormat("Cannot read open trade comment %s",m_names[i]); }
      }
      
      // Finding the minimum bands for each currency
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
      f_barSizeTSAvg = NormalizeDouble((1/MarketInfo(m_names[i],MODE_POINT)) * f_barSizeTSAvg / i_bandsHistory, 0);
      f_overlap = f_overlap / i_bandsHistory;
      Alert(m_names[i]," Ratio: ",f_barSizeTSAvg/m_bandsTSAvg[i]);
      if ((f_barSizeTSAvg/m_bandsTSAvg[i] > 0.11) && (m_sequence[i][0]<0)) {        // if noisy and no sequence already live -> exclude pair
         m_tradeFlag[i] = false;
         Alert(m_names[i]," removed. Ratio: ",f_barSizeTSAvg/m_bandsTSAvg[i]);
      }   
      Alert(m_names[i]," Overlap Measure: ",f_overlap);
   }
   
   // Setting the Global variables
   GlobalVariableSet("gv_productMagicNumber",-1);
   GlobalVariableSet("gv_slowFilter",-1);
   GlobalVariableSet("gv_creditProductMagicNumber",-1);
   GlobalVariableSet("gv_creditAmount",0.0);
   if (GlobalVariableCheck("gv_creditBalance")) { f_creditBalance = GlobalVariableGet("gv_creditBalance"); }
   else { GlobalVariableSet("gv_creditBalance",0.0); }
   if (f_creditBalance>0) {
	   for(int i=0; i<i_namesNumber; i++) {
		// m_sequence[i][1] is a negative number, the GVs are always amounts so penalty will be negative
		if (m_sequence[i][1]>-f_creditPenaltyThreshold) { m_credit[i] = -f_creditPenalty; }
		else { m_credit[i] = 0.0; }
	   }
   }
   
   Alert ("Function init() triggered at start for ",symb);// Alert
   if (IsDemo() == false) { Alert("THIS IS NOT A DEMO RUN"); }
   
//---
   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//| Expert testing function called before deinit only on testing mode|
//+------------------------------------------------------------------+
double OnTester()
  {
   double f_wins = TesterStatistics(STAT_PROFIT_TRADES);
   double f_losses = TesterStatistics(STAT_LOSS_TRADES);
   double f_criterion = f_wins / (f_wins + f_losses);
   
   // write to file
   //if (IsTesting()) {
   //   h=FileOpen("testResults.csv",FILE_WRITE|FILE_CSV|FILE_READ);
   //   if (h!=INVALID_HANDLE) {
   //      FileSeek(h,0,SEEK_END);
   //      FileWrite(h,i_counter,f_wins,f_losses,f_criterion); 
   //      FileClose(h); }
   //   else {
   //      Print("fileopen failed, error:",GetLastError()); 
   //   }
   //}
//---
   return(f_criterion);
  }
  
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   Alert ("Function deinit() triggered at exit for ",symb);// Alert
   
   if (IsTesting()) {
      Print ("Win Ratio:",TesterStatistics(STAT_CUSTOM_ONTESTER));
   }
   
   // TIMER KILL
   EventKillTimer();
   
   return;
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTimer() //void OnTick()
  {

// VARIABLE DECLARATIONS /////////////////////////////////////////////////////////////////////////////////////////////////////////
   int 
   ticket,
   i_orderMagicNumber,i_openOrderNo = 0;
   bool res,isNewBar,temp_flag,b_pending=false;
   double
   temp_vwap=-1.0,
   SL,TP,BID,ASK,f_fastFilterPrev=0.0,f_central=0.0,f_loss,
   f_orderOpenPrice,f_orderStopLoss,
   f_bollingerBandPrev = 0.0,f_bollingerBand = 0.0,temp_T1=0;
   int m_signal[]; 
   bool m_isPositionOpen[];
   bool m_isPositionPending[];
   int m_positionDirection[];
   int m_lastTicketOpenTime[];
   double m_fastFilter[];
   string s_comment,s_orderSymbol,s_adjFlag="";
   
// PRELIMINARY PROCESSING ///////////////////////////////////////////////////////////////////////////////////////////////////////////
   ArrayResize(m_signal,i_namesNumber,0);
   ArrayResize(m_isPositionOpen,i_namesNumber,0);
   ArrayResize(m_isPositionPending,i_namesNumber,0);
   ArrayResize(m_positionDirection,i_namesNumber,0);
   ArrayResize(m_lastTicketOpenTime,i_namesNumber,0);
   ArrayResize(m_fastFilter,i_namesNumber,0);
   ArrayInitialize(m_signal,0);
   ArrayInitialize(m_isPositionOpen,false);
   ArrayInitialize(m_isPositionPending,false);
   ArrayInitialize(m_positionDirection,0);
   ArrayInitialize(m_lastTicketOpenTime,-1);
   ArrayInitialize(m_fastFilter,0);
   count++;
   isNewBar=isNewBar();
   if(Bars < 100)                       // Not enough bars
     {
      Alert("Not enough bars in the window. EA doesn't work.");
      return;                                   // Exit start()
     }
   if(Work==false)                              // Critical error
     {
      Alert("Critical error. EA doesn't work.");
      return;                                   // Exit start()
     }

// UPDATE STATUS/////////////////////////////////////////////////////////////////////////////////////////////////////
for(int i=0; i<i_namesNumber; i++) {
      if (m_tradeFlag[i]==true) {
      		if (m_ticket[i]>0) {
			res = OrderSelect(m_ticket[i],SELECT_BY_TICKET);
			if (res) {
				if (OrderCloseTime()>0) {			// if closed
					if (readTradeComment(m_ticket[i],m_names[i],temp_sequence)) {
						if (temp_sequence[1]+temp_sequence[5]>0) {	//ie trade sequence closed positive 
							m_sequence[i][0] = -1;
							m_sequence[i][1] = 0;
							m_sequence[i][2] = 0; 
							f_creditBalance = f_creditBalance - f_creditPenaltyAmount; 
							GlobalVariableSet("gv_creditBalance",f_creditBalance);
						}
						else {
						   // dont copy over slow filter because it may have been modified externally
						   m_sequence[i][1] = temp_sequence[1] + temp_sequence[5];
						   m_sequence[i][2] = temp_sequence[2];
						}
						m_isPositionOpen[i]=false;
						m_isPositionPending[i] = false;
						m_positionDirection[i] = 0;
						m_ticket[i] = 0;
					}
				}
				else {
					if (OrderType()==OP_BUY) { 
						m_isPositionOpen[i]=true;
						m_isPositionPending[i] = false;
						m_lastTicketOpenTime[i] = iBarShift(m_names[i],timeFrame,OrderOpenTime(),true);
						m_positionDirection[i] = 1;	
						i_openOrderNo = i_openOrderNo + 1; }
					else if (OrderType()==OP_SELL) { 
						m_isPositionOpen[i]=true;
						m_isPositionPending[i] = false;
						m_lastTicketOpenTime[i] = iBarShift(m_names[i],timeFrame,OrderOpenTime(),true);
						m_positionDirection[i] = -1;	
						i_openOrderNo = i_openOrderNo + 1; }
					else if (OrderType()==OP_SELLSTOP || OrderType()==OP_SELLLIMIT) { 								// pending
						m_isPositionOpen[i]=false;
						m_isPositionPending[i] = true; 
						b_pending = true;
						m_positionDirection[i] = -1; }
					else if (OrderType()==OP_BUYSTOP || OrderType()==OP_BUYLIMIT) { 								// pending
						m_isPositionOpen[i]=false;
						m_isPositionPending[i] = true; 
						b_pending = true;
						m_positionDirection[i] = 1; 
					}
				}
			}
			else { Alert("Failed to select trade: ",m_ticket[i]); }
		}
      }
}

// SETTING EXTERNALLY THE SLOW FILTER VALUE USING GLOBAL VARIABLES /////////////////////////////////////
if (slowfilter_productMagicNumber>0) {
	int temp_i = slowfilter_productMagicNumber - i_stratMagicNumber*100 - 1;
	if (slowfilter_value<0) {	
		// if slow filter not provided, set to open order price
		res = OrderSelect(m_ticket[i],SELECT_BY_TICKET);
		if (res) { m_sequence[temp_i][0] = NormalizeDouble(OrderOpenPrice(),(int)MarketInfo(m_names[temp_i],MODE_DIGITS)); 
			   Alert("The slow filter for product ",m_names[temp_i]," was changed to ",m_sequence[temp_i][0]);
		}
		else { Alert("Slow filter change failed for product ",m_names[temp_i]); }
		// if slow filter not provided, set to last fast filter value
		/**
		if (m_positionDirection[temp_i]<0) {
			m_sequence[temp_i][0] = NormalizeDouble(iCustom(m_names[temp_i],0,"petousis_supersmoother",m_filter[temp_i][1],filter_history,1,1) + MarketInfo(m_names[temp_i],MODE_POINT),(int)MarketInfo(m_names[temp_i],MODE_DIGITS));
			Alert("The slow filter for product ",m_names[temp_i]," was changed to ",m_sequence[temp_i][0]); }
		else if (m_positionDirection[temp_i]>0) {
			m_sequence[temp_i][0] = NormalizeDouble(iCustom(m_names[temp_i],0,"petousis_supersmoother",m_filter[temp_i][1],filter_history,1,1) - MarketInfo(m_names[temp_i],MODE_POINT),(int)MarketInfo(m_names[temp_i],MODE_DIGITS));
			Alert("The slow filter for product ",m_names[temp_i]," was changed to ",m_sequence[temp_i][0]); }
		else { Alert("The slow filter change failed because position direction is 0. There is no existing trade."); }
		**/
	}
	else { m_sequence[temp_i][0] = slowfilter_value;
		Alert("The slow filter for product ",m_names[temp_i]," was changed to ",m_sequence[temp_i][0]); 
	}
	// resetting
   	GlobalVariableSet("gv_productMagicNumber",-1);
   	GlobalVariableSet("gv_slowFilter",-1);
}

// GIVING CREDIT TO STRUGGLING SEQUENCE BY PENALISING OTHERS
temp_i = (int)GlobalVariableGet("gv_creditProductMagicNumber") - i_stratMagicNumber*100 - 1;
if (temp_i>0) {			// only enter loop if there is new amount to be credited
	for(int i=0; i<i_namesNumber; i++) {
		if ((int)MathFloor(temp_i/100)==i_stratMagicNumber && temp_i==i) {
			m_credit[i] = MathMax(0.0,m_credit[i]) + GlobalVariableGet("gv_creditAmount");
		}
		else if (m_sequence[i][1]>-f_creditPenaltyThreshold) {
			m_credit[i] = -f_creditPenalty;
		}
		else { m_credit[i] = 0.0; }
	}
	GlobalVariableSet("gv_creditProductMagicNumber",-1);
	GlobalVariableSet("gv_creditBalance",f_creditBalance+GlobalVariableGet("gv_creditAmount"));
	GlobalVariableSet("gv_creditAmount",0);
}

// Make sure rest of ontimer() does not run continuously when not needed
   if ((Minute()>55 || Minute()<15) || b_pending) {   

// INDICATOR BUFFERS ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      for(int i=0; i<i_namesNumber; i++) {
      if (m_tradeFlag[i]==true) {
      
      	m_fastFilter[i] = iCustom(m_names[i],0,"petousis_supersmoother",m_filter[i][1],filter_history,1,1);
	      f_fastFilterPrev = iCustom(m_names[i],0,"petousis_supersmoother",m_filter[i][1],filter_history,1,2);
	      if (m_sequence[i][0]<0) {	// new sequence
	 	      f_bollingerBand = iBands(m_names[i],timeFrame,(int)m_filter[i][0],bollinger_deviations,0,0,bollinger_mode,1);
	 	      f_bollingerBandPrev = iBands(m_names[i],timeFrame,(int)m_filter[i][0],bollinger_deviations,0,0,bollinger_mode,2); }
	      else {				
	 	      f_bollingerBand = m_sequence[i][0];
		      f_bollingerBandPrev = f_bollingerBand;
	      }
	      temp_T1 = (m_fastFilter[i] - f_bollingerBand)*(f_fastFilterPrev - f_bollingerBandPrev);
         
          if (temp_T1 < 0) {
            if (m_sequence[i][2]<1) {         // new sequence, so update the pips
               f_central = iBands(m_names[i],timeFrame,(int)m_filter[i][0],bollinger_deviations,0,0,MODE_MAIN,1);
	            m_bollingerDeviationInPips[i] = NormalizeDouble(MathMax((1/MarketInfo(m_names[i],MODE_POINT)) * 2 * MathAbs(f_central-f_bollingerBand), m_bandsTSAvg[i]),0);
            }
	         // signal only fires if no open trade or opposite open trade, if no ticket was opened this bar
            if (m_fastFilter[i]>f_bollingerBand && m_positionDirection[i]<1 && iBars(m_names[i],timeFrame)>m_lastTicketOpenTime[i]) {
               m_signal[i] = 1;
            }
	         else if (m_fastFilter[i]<f_bollingerBand && m_positionDirection[i]>-1 && iBars(m_names[i],timeFrame)>m_lastTicketOpenTime[i]) {
               m_signal[i] = -1;
            }
            else {
               m_signal[i] = 0;
            }
		   }
         else { m_signal[i] = 0; }
      }
      }



// ORDERS ACCOUNTING ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
if (b_lockIn) {
   for(int k=OrdersTotal()-1; k>=0; k--) {
      temp_flag = OrderSelect(k,SELECT_BY_POS);
      if (temp_flag) {
         i_orderMagicNumber = OrderMagicNumber();
         if (((double)i_orderMagicNumber/100 > i_stratMagicNumber) && ((double)i_orderMagicNumber/100 < i_stratMagicNumber+1)) {        //order belongs to strategy
            f_orderOpenPrice = OrderOpenPrice();
            f_orderStopLoss = OrderStopLoss();
            s_orderSymbol = OrderSymbol();
            if (OrderType()==OP_BUY) {
               if (f_orderStopLoss < f_orderOpenPrice) {             // if not already locked in
                  if (MarketInfo(s_orderSymbol,MODE_BID) >= f_orderOpenPrice + (f_orderOpenPrice-f_orderStopLoss)) {
                     temp_flag = OrderModify(OrderTicket(),f_orderOpenPrice,f_orderOpenPrice+MarketInfo(s_orderSymbol,MODE_SPREAD)*MarketInfo(s_orderSymbol,MODE_POINT),OrderTakeProfit(),0);
                     if (temp_flag == false) { Alert("Could not lockin order"); }
                  }
               }
            }
            else {
               if (f_orderStopLoss > f_orderOpenPrice) {             // if not already locked in
                  if (MarketInfo(s_orderSymbol,MODE_ASK) <= f_orderOpenPrice - (f_orderStopLoss - f_orderOpenPrice)) {
                     temp_flag = OrderModify(OrderTicket(),f_orderOpenPrice,f_orderOpenPrice-MarketInfo(s_orderSymbol,MODE_SPREAD)*MarketInfo(s_orderSymbol,MODE_POINT),OrderTakeProfit(),0);
                     if (temp_flag == false) { Alert("Could not lockin order"); }
                  }
               }
            }
         }
      }
      else { Alert("Order could not be selected for lock in"); }
   }
}
   
// CLOSING ORDERS //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 
 for(int i=0; i<i_namesNumber; i++) {
 if (m_tradeFlag[i]==true) {
      if (m_signal[i]<0 && m_positionDirection[i]==1) {
            RefreshRates();
            Alert("Attempt to close Buy ",m_ticket[i]); 
			res = OrderSelect(m_ticket[i],SELECT_BY_TICKET);
			if (m_isPositionPending[i]==true) {
				res = OrderDelete(m_ticket[i]); }
			else { res = OrderClose(m_ticket[i],OrderLots(),MarketInfo(m_names[i],MODE_BID),100); }         // slippage 100, so it always closes
            if (res==true) {
               Alert("Order Buy closed."); 
               break;
            }
            if (Fun_Error(GetLastError())==1) {
               continue;
            }
            return;
      }
      if (m_signal[i]>0 && m_positionDirection[i]==-1) {
         if ( m_signal[i]>0 && m_positionDirection[i]==-1) {
            RefreshRates();
            Alert("Attempt to close Sell ",m_ticket[i]); 
			res = OrderSelect(m_ticket[i],SELECT_BY_TICKET);
			if (m_isPositionPending[i]==true) {
				res = OrderDelete(m_ticket[i]); }
			else { res = OrderClose(m_ticket[i],OrderLots(),MarketInfo(m_names[i],MODE_ASK),100); }
            if (res==true) {
               Alert("Order Sell closed. "); 
               break;
            }
            if (Fun_Error(GetLastError())==1) {
               continue;
            }
            return;
         }
      }
  }
  }
 
 // OPENING ORDERS //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   for(int i=0; i<i_namesNumber; i++) {
   if (m_tradeFlag[i]==true) {
      if (((m_signal[i]>0) || (m_signal[i]<0)) && !(b_noNewSequence && m_sequence[i][0]<0))   // Send order when receive buy or sell signal 
        {
         // Open Buy
         if (m_signal[i]>0) 
           {                                       // criterion for opening Buy
            RefreshRates();                        // Refresh rates
            ASK = MarketInfo(m_names[i],MODE_ASK);
            SL=NormalizeDouble(ASK - m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));     // Calculating SL of opened
            TP=NormalizeDouble(ASK + m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));   // Calculating TP of opened
            
            if (m_isPositionPending[i]==false && m_isPositionOpen[i]==false) {       // if no position and no pending -> send pending order
               // LOTS
               if (-m_sequence[i][1]<f_creditPenaltyThreshold || m_credit[i]>0) { 
                  f_loss = -m_sequence[i][1] + m_credit[i]; 
		  m_sequence[i][1] = -f_loss; } 
               else { 
	       	  f_loss = -m_sequence[i][1]; 
	       }
               if (f_loss>m_profitInUSD[i]*f_percWarp) {
      	    	   m_lots[i] = NormalizeDouble(MathMax(m_lotMin[i],(f_loss/f_percWarp) / m_accountCcyFactors[i] / m_bollingerDeviationInPips[i]),m_lotDigits[i]);
         	    }
         	    else {
         	    	m_lots[i] = NormalizeDouble(MathMax(m_lotMin[i], m_profitInUSD[i] / m_accountCcyFactors[i] / m_bollingerDeviationInPips[i]),m_lotDigits[i]);
         	    }
         	    // COMMENT
               if (m_sequence[i][0] < 0) { 
   	       		temp_vwap = m_fastFilter[i] - MarketInfo(m_names[i],MODE_POINT); 
   	       		s_adjFlag = ""; } 
      		   else if (m_sequence[i][0]>0 && (ASK-m_sequence[i][0]>f_adjustLevel*(ASK-SL))) {
      			   temp_vwap = m_fastFilter[i] - MarketInfo(m_names[i],MODE_POINT); 
      			   s_adjFlag = "A"; }	// update if last move too big
      		   else { temp_vwap = m_sequence[i][0]; 
      		         s_adjFlag = "";
               }
               s_comment = StringConcatenate(IntegerToString(m_myMagicNumber[i]),"_",DoubleToStr(temp_vwap,(int)MarketInfo(m_names[i],MODE_DIGITS)),s_adjFlag,"_",DoubleToStr(-f_loss,2),"_",DoubleToStr(m_sequence[i][2]+1,0));
               ticket=OrderSend(m_names[i],OP_BUYLIMIT,m_lots[i],ASK,slippage,SL,TP,s_comment,m_myMagicNumber[i]); //Opening Buy
               Print("OrderSend returned:",ticket," Lots: ",m_lots[i]); 
               if (ticket < 0)  {                    
                  Alert("OrderSend failed with error #", GetLastError());
                  Alert("Ask: ",ASK,". SL: ",SL,". TP: ",TP);
                  Alert("Loss: ",-f_loss,". SLinUSD: ",m_profitInUSD[i],". Factor: ",m_accountCcyFactors[i],". Pips: ",m_bollingerDeviationInPips[i]);
               }
               else {			// Success :) 
                  m_sequence[i][0] = temp_vwap;
                  m_sequence[i][2] = m_sequence[i][2] + 1;                          // increment trade number
                  Alert ("Opened pending order Buy:",ticket,",Symbol:",m_names[i]," Lots:",m_lots[i]);
		  m_ticket[i] = ticket;
                  //PlaySound("bikehorn.wav");
                  if (b_sendEmail) { 
                     res = SendMail("VWAP TRADE ALERT","Algo bought "+m_names[i]+" "+DoubleToStr(Period(),0)); 
                     if (res==false) { Alert(m_names[i]+" "+DoubleToStr(Period(),0)," Email could not be sent.");  }
                  }
               }
            }
            else if (m_isPositionPending[i]==true && m_positionDirection[i]==1) {     // if pending order exists -> modify pending order
               res = OrderModify(m_ticket[i],ASK,SL,TP,0);
               if (res) { Print("Order modified successfully:",m_names[i]); }
               else { Alert(m_names[i],": Order modification failed with error #", GetLastError()); }
            }
            else { Alert("ERROR - ",m_names[i]," System is sending a buy signal, but it is neither opening nor modifying."); }
           }
           // Open Sell
         if (m_signal[i]<0) 
           {                                       // criterion for opening Sell
            RefreshRates();                        // Refresh rates
            BID = MarketInfo(m_names[i],MODE_BID);
            SL=NormalizeDouble(BID + m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));     // Calculating SL of opened
            TP=NormalizeDouble(BID - m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));   // Calculating TP of opened
            if (m_isPositionPending[i]==false && m_isPositionOpen[i]==false) {
               // LOTS
               if (-m_sequence[i][1]<f_creditPenaltyThreshold || m_credit[i]>0) { 
                  f_loss = -m_sequence[i][1] + m_credit[i]; 
		  m_sequence[i][1] = -f_loss; } 
               else { 
	       	  f_loss = -m_sequence[i][1]; 
	       }
               if (f_loss>m_profitInUSD[i]*f_percWarp) {
         	    	m_lots[i] = NormalizeDouble(MathMax(m_lotMin[i],(f_loss/f_percWarp) / m_accountCcyFactors[i] / m_bollingerDeviationInPips[i]),m_lotDigits[i]);
         	    }
         	    else {
         	    	m_lots[i] = NormalizeDouble(MathMax(m_lotMin[i], m_profitInUSD[i] / m_accountCcyFactors[i] / m_bollingerDeviationInPips[i]),m_lotDigits[i]);
         	    }
         	    // COMMENT
                if (m_sequence[i][0] < 0) { 
   	       		temp_vwap = m_fastFilter[i] + MarketInfo(m_names[i],MODE_POINT); 
   	       		s_adjFlag = ""; } 
         		else if (m_sequence[i][0]>0 && (m_sequence[i][0]-BID>f_adjustLevel*(SL-BID))) {
         			temp_vwap = m_fastFilter[i] + MarketInfo(m_names[i],MODE_POINT); 
         			s_adjFlag = "A"; }	// update if last move too big
         		else { temp_vwap = m_sequence[i][0]; 
         		   s_adjFlag = "";
               }
               s_comment = StringConcatenate(IntegerToString(m_myMagicNumber[i]),"_",DoubleToStr(temp_vwap,(int)MarketInfo(m_names[i],MODE_DIGITS)),s_adjFlag,"_",DoubleToStr(-f_loss,2),"_",DoubleToStr(m_sequence[i][2]+1,0));
               ticket=OrderSend(m_names[i],OP_SELLLIMIT,m_lots[i],BID,slippage,SL,TP,s_comment,m_myMagicNumber[i]); //Opening Sell
               Print("OrderSend returned:",ticket," Lots: ",m_lots[i]); 
               if (ticket < 0)     {                 
                  Alert("OrderSend failed with error #", GetLastError());
                  Alert("Bid: ",BID,". SL: ",SL,". TP: ",TP);
                  Alert("Loss: ",-f_loss,". SLinUSD: ",m_profitInUSD[i],". Factor: ",m_accountCcyFactors[i],". Pips: ",m_bollingerDeviationInPips[i]);
               }
               else {				// Success :)
                  m_sequence[i][0] = temp_vwap;
                  m_sequence[i][2] = m_sequence[i][2] + 1;                          // increment trade number
                  Alert ("Opened pending order Sell ",ticket,",Symbol:",m_names[i]," Lots:",m_lots[i]);
   				  m_ticket[i] = ticket;
                  //PlaySound("bikehorn.wav");
                  if (b_sendEmail) { 
                     res = SendMail("VWAP TRADE ALERT","Algo sold "+m_names[i]+" "+DoubleToStr(Period(),0)); 
                     if (res==false) { Alert(m_names[i]+" "+DoubleToStr(Period(),0)," Email could not be sent.");  }
                  }
               }
            }
            else if (m_isPositionPending[i]==true && m_positionDirection[i]==-1) {
               res = OrderModify(m_ticket[i],BID,SL,TP,0);
               if (res) { Print("Order modified successfully:",m_names[i]); }
               else { Alert(m_names[i],": Order modification failed with error #", GetLastError()); }
               }
            else { Alert("ERROR - ",m_names[i]," System is sending a sell signal, but it is neither opening nor modifying."); }
           }                                
        }
    }
    }
                  
     
  // SYSTEM SAFETY //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////   
     
   
   /**
   // Alert for products with high consecutive losses
   if (isNewBar) {
      //string s_losses = "_";
      Alert("Strategy: ",i_stratMagicNumber,". Timeframe: ",timeFrame,". New bar at ",TimeCurrent());
      Alert("Following products are on >3*SL losses:");
      for(int i=0; i<i_namesNumber; i++) {
         if (m_sequence[i][1]>=3*(MarketInfo(m_names[i,0],MODE_LOTSIZE)*StrToDouble(m_names[i,3])*StrToDouble(m_names[i,4]))) {
            //s_losses = StringConcatenate(s_losses,"_",m_names[i,0]);
            PrintFormat("Product: %s is on %d ",m_names[i,0],m_sequence[i][1]);
         }
      }
      //Alert(MarketInfo("SPX500",MODE_TRADEALLOWED));
      //Alert(MarketInfo("WTI",MODE_TRADEALLOWED));
      //Alert(MarketInfo("BRENT",MODE_TRADEALLOWED));
   }
   **/
   // measure execution time
   //uint time=GetTickCount()-start;
   //Print("This run took:",time,"msec");
     
   return;                                      // exit start()
   }
   else { return; }
  }
  
  // FUNCTIONS  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  
  
  bool isPositionOpen(int myMagicNumber, string symbol)
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol && (OrderType()==OP_BUY || OrderType()==OP_SELL) )
        {
         return true;
        }
     }
   return false;
  }
  
  int getName(string s1, string s2)          // gives index
  {
   string temp1 = StringConcatenate(s1,s2);
   string temp2 = StringConcatenate(s2,s1);
   for(int i=0; i<i_namesNumber; i++) {
      if (StringCompare(temp1,StringSubstr(m_names[i],0,6),false)==0) { return i; }
      if (StringCompare(temp2,StringSubstr(m_names[i],0,6),false)==0) { return i; }
   }
   return -1;
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
      	output[5] = OrderProfit() + OrderCommission() + OrderSwap(); }
          else {
      	output[1] = StrToDouble(result[2]);   // cum loss
      	output[3] = 0.0;
      	output[5] = 0.0;
          }
          output[4] = OrderTicket();
          temp = StringFind(result[3],"[");
          if (temp<0) {
             output[2] = StrToDouble(result[3]); } // trade number
          else if (temp==1) {
             output[2] = StrToDouble(StringSubstr(result[3],0,1)); }
          else if (temp==2) {
             output[2] = StrToDouble(StringSubstr(result[3],0,2)); }
          return true;
       }
       else  { return false; }
}
  
  
  double accCcyFactor(string symbol)
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
      if (StringCompare(StringSubstr(symbol,0,3),AccountCurrency(),false)==0) {
          if (StringCompare(StringSubstr(symbol,3,3),"JPY",false)==0) {
              result = 100 / MarketInfo(symbol,MODE_BID); }
          else { result = 1.0 / MarketInfo(symbol,MODE_BID); }
      }
      else if (StringCompare(StringSubstr(symbol,3,3),AccountCurrency(),false)==0) {
              result = 1.0; }
      else if (StringCompare(StringSubstr(symbol,0,3),"WTI",false)==0) {
            result = 10.0; 
         }
      else { 
         int k = getName(StringSubstr(symbol,3,3),"USD");
         if (k>=0) {
            if (StringFind(m_names[k],"USD")==0) {
	    	      if (StringFind(m_names[k],"USDJPY")>-1) { result = 100 / MarketInfo(m_names[k],MODE_BID); }
		         else { result = 1.0 / MarketInfo(m_names[k],MODE_BID); }
	         }
            else if (StringFind(m_names[k],"USD")==3) { result = MarketInfo(m_names[k],MODE_BID); } 
         } 
         else {
            result = 1.0;       // not a currency
         }
      }
      return result;
}
  
  
  
  bool isNewBar()
  {
      static datetime lastbar=0;
      datetime curbar = Time[0];
      if (lastbar!=curbar)
      {
         lastbar = curbar;
         //Alert("new bar");
         return (true);
      }
      else
      {
         return(false);
      }
  }
  
  
  int Fun_Error(int Error)                        // Function of processing errors
  {
   switch(Error)
     {                                          // Not crucial errors            
      case  4: Alert("Trade server is busy. Trying once again..");
         Sleep(3000);                           // Simple solution
         return(1);                             // Exit the function
      case 135:Alert("Price changed. Trying once again..");
         RefreshRates();                        // Refresh rates
         return(1);                             // Exit the function
      case 136:Alert("No prices. Waiting for a new tick..");
         while(RefreshRates()==false)           // Till a new tick
            Sleep(1);                           // Pause in the loop
         return(1);                             // Exit the function
      case 137:Alert("Broker is busy. Trying once again..");
         Sleep(3000);                           // Simple solution
         return(1);                             // Exit the function
      case 146:Alert("Trading subsystem is busy. Trying once again..");
         Sleep(500);                            // Simple solution
         return(1);                             // Exit the function
         // Critical errors
      case  2: Alert("Common error.");
         return(0);                             // Exit the function
      case  5: Alert("Old terminal version.");
         Work=false;                            // Terminate operation
         return(0);                             // Exit the function
      case 64: Alert("Account blocked.");
         Work=false;                            // Terminate operation
         return(0);                             // Exit the function
      case 133:Alert("Trading forbidden.");
         return(0);                             // Exit the function
      case 134:Alert("Not enough money to execute operation.");
         return(0);                             // Exit the function
      default: Alert("Error occurred: ",Error);  // Other variants   
         return(0);                             // Exit the function
     }
  }
  

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
//---
   
  }
//+------------------------------------------------------------------+
