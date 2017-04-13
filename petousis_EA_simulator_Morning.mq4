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
**/

// DEFINITIONS ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#define NAMESNUMBERMAX 50                 // this is the max number of names currently - it can be set higher if needed

// INPUTS ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//input switches
input string s_inputFileName = "TF_DEMO_M5_Morning.txt"; 
bool b_orderSizeByLabouchere = true;
bool b_sendEmail=false;
input int i_stratMagicNumber = 90;		// Always positive
int const i_hourEndFriday = 23;

// TRADE ACCOUNTING VARIABLES ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
int const slippage =10;           // in points
//double const b_commission = 6*Point+10*Point;  // commission + safety net
//int const i_maxDrawdown = 10000;      // in USD max drawdown
int const timeFrame=Period();        
bool Work = true;             //EA will work
string const symb =Symbol();
int m_magicNumber[NAMESNUMBERMAX][2];  // Magic Numbers
double m_lots[NAMESNUMBERMAX];
double m_accountCcyFactors[NAMESNUMBERMAX];
string m_names[NAMESNUMBERMAX][8];
int m_state[NAMESNUMBERMAX,2];		// 0:no buy/sell trade 1:pending 2:open
bool m_doneForTheDay[NAMESNUMBERMAX];
int m_sequence[NAMESNUMBERMAX][2];
double m_openPrice[][2];
double m_stopLoss[][2];
double m_takeProfit[][2];
double m_SR[][2];
double m_pips[];

// OTHER VARIABLES //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
int h;
int i_labouchereLosses=0,i_namesNumber=0;
int i_ordersHistoryTotal=OrdersHistoryTotal();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   
   // TIMER FREQUENCY - APPARENTLY NO SERVER CONTACT FOR MORE THAN 30SEC WILL CAUSE REAUTHENTICATION ADDING CONSIDERABLE DELAY, SO THEREFORE USE 15SEC INTERVAL
   EventSetTimer(15);
   //Alert(Bars,"____",iBarShift(symb,timeFrame,TimeCurrent(),true));
   
   // READ IN THE FILE
   string m_rows[6];       // name, trade Y/N, lots, sleep range start, sleep range end
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
   ArrayInitialize(m_magicNumber,0);
   ArrayInitialize(m_lots,0.0);
   ArrayInitialize(m_accountCcyFactors,0.0);
   ArrayInitialize(m_state,0);
   ArrayInitialize(m_doneForTheDay,false);
   ArrayInitialize(m_sequence,0);
   ArrayInitialize(m_takeProfit,0);
   ArrayInitialize(m_stopLoss,0);
   ArrayInitialize(m_openPrice,0);
   ArrayInitialize(m_SR,0);
   ArrayInitialize(m_pips,0);
   
   // Resize arrays once number of products known
   ArrayResize(m_names,i_namesNumber,0);
   ArrayResize(m_magicNumber,i_namesNumber,0);
   ArrayResize(m_lots,i_namesNumber,0);
   ArrayResize(m_accountCcyFactors,i_namesNumber,0);
   ArrayResize(m_state,i_namesNumber,0);
   ArrayResize(m_doneForTheDay,i_namesNumber,0);
   ArrayResize(m_sequence,i_namesNumber,0);
   ArrayResize(m_takeProfit,i_namesNumber,0);
   ArrayResize(m_stopLoss,i_namesNumber,0);
   ArrayResize(m_openPrice,i_namesNumber,0);
   ArrayResize(m_SR,i_namesNumber,0);
   ArrayResize(m_pips,i_namesNumber,0);
   for(int i=0; i<i_namesNumber; i++) {
      // m_names array
      temp = StringSplit(arr[i],u_sep,m_rows);
      if (temp == ArraySize(m_rows)) {
         for (int j=0; j<ArraySize(m_rows); j++) {
            m_names[i][j] = m_rows[j];
         }
      }
      else { Alert("Failed to read row number %d, Number of elements read = %d instead of %d",i,temp,ArraySize(m_rows)); }
      // magic numbers
      m_magicNumber[i,0] = getMagicNumber(m_names[i,0],i_stratMagicNumber);
      m_magicNumber[i,1] = -1 * m_magicNumber[i,0];
      // initialize m_accountCcyFactors
      /**
      If our SL/TP is given in pips, then: For 1lot USDXXX, 1pip is USD1/USDXXX so the formula is  
      Lots = 1/USDXXX * cash(USD) / #pips
      For 1lot USDJPY, 1pip is JPY100 so the formula becomes Lots = 100/USDXXX * cash(USD) / #pips
      For 1lot XXXUSD 1pip is USD1 so the formula is Lots = cash(USD) / #pips
      For 1lot XAUUSD 1pip is USD1 so the formula is Lots = cash(USD) / #pips
      For 1lot WTI 1pip is USD10 so the formula is Lots = 1/10 *cash(USD) / #pips
      For 1lot CC1CC2, 1pip is USD1/USDCC2 so the formula is Lots = 1/USDCC2 * cash(USD) / #pips
      For 1lot CC1JPY, 1pip is USD1/USDJPY so the formula is Lots = 100/USDJPY * cash(USD) / #pips
      For 1lot CC1CC2, 1pip is USD1/CC2USD so the formula is Lots = CC2USD * cash(USD) / #pips
      **/
      if (StringCompare(StringSubstr(m_names[i,0],0,3),AccountCurrency(),false)==0) {
          if (StringCompare(StringSubstr(m_names[i,0],3,3),"JPY",false)==0) {
              m_accountCcyFactors[i] = 100 / MarketInfo(m_names[i,0],MODE_BID); }
          else { m_accountCcyFactors[i] = 1.0 / MarketInfo(m_names[i,0],MODE_BID); }
      }
      else if (StringCompare(StringSubstr(m_names[i,0],3,3),AccountCurrency(),false)==0) {
              m_accountCcyFactors[i] = 1.0; }
      else if (StringCompare(StringSubstr(m_names[i,0],0,3),"WTI",false)==0) {
            m_accountCcyFactors[i] = 1.0 / 10; 
         }
      else { 
         int k = getName(StringSubstr(m_names[i,0],3,3),"USD");
         if (k>=0) {
            if (StringCompare(m_names[k,0],"USDJPY",false)==0) {
               m_accountCcyFactors[i] = 100 / MarketInfo(m_names[k,0],MODE_BID); }
            else if (StringFind(m_names[k,0],"USD")==0) {
               m_accountCcyFactors[i] = 1.0 / MarketInfo(m_names[k,0],MODE_BID); }
            else if (StringFind(m_names[k,0],"USD")==3) {
               m_accountCcyFactors[i] = MarketInfo(m_names[k,0],MODE_BID); } 
         } 
         else {
            m_accountCcyFactors[i] = 1.0;       // not a currency
         }
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
   i_ticketPending=-1,i_ticketOpen,i_ticket,i_SRInMin,i_orderType,
   i_win=0,i_loss=0;
   bool res,isNewBar,success;
   double
   f_weightedLosses = 0.0,
   f_low,f_high,f_digits,f_average,f_SR=0;
   int m_signal[][2]; 	// -1: close 0: do nothing 1:open pending
   bool m_openBuy[];
   bool m_openSell[];
   bool m_closeBuy[];
   bool m_closeSell[];
   string s_comment,s_orderSymbol;
   double temp_sequence[2];
   
// PRELIMINARY PROCESSING ///////////////////////////////////////////////////////////////////////////////////////////////////////////
   ArrayResize(m_signal,i_namesNumber,0);
   ArrayResize(m_openBuy,i_namesNumber,0);
   ArrayResize(m_openSell,i_namesNumber,0);
   ArrayResize(m_closeBuy,i_namesNumber,0);
   ArrayResize(m_closeSell,i_namesNumber,0);
   ArrayInitialize(m_signal,0);
   ArrayInitialize(m_openBuy,false);
   ArrayInitialize(m_openSell,false);
   ArrayInitialize(m_closeBuy,false);
   ArrayInitialize(m_closeSell,false);
   
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

// ORDERS ACCOUNTING
for(int i=0; i<i_namesNumber; i++) {

   if (Hour()==0) {				// At midnight reset
	   m_doneForTheDay[i] = false;
	}
   
	if (~m_doneForTheDay[i]) {
	
		// if there is already a closed trade today and we hit TP -> done for the day
		res = readLastTradeComment(m_magicNumber[i,0],m_names[i,0],true,temp_sequence);
		if (res && temp_sequence[0]>0) { m_doneForTheDay[i] = true; }
		res = readLastTradeComment(m_magicNumber[i,1],m_names[i,0],true,temp_sequence);
		if (res && temp_sequence[0]>0) { m_doneForTheDay[i] = true; }

		// update states - buy
		i_ticketPending = ticketPositionPendingBuy(m_magicNumber[i,0],m_names[i,0]);
		i_ticketOpen = ticketPositionOpenBuy(m_magicNumber[i,0],m_names[i,0]);
		if (i_ticketPending>0 && i_ticketOpen>0) { Alert(m_names[i,0],": ERROR - We have two trades in same direction."); }
		else if (i_ticketPending>0 && i_ticketOpen<0) { m_state[i,0] = 1; }
		else if (i_ticketPending<0 && i_ticketOpen>0) { m_state[i,0] = 2; }
		else { m_state[i,0] = 0; }
		// update states - sell
		i_ticketPending = ticketPositionPendingSell(m_magicNumber[i,1],m_names[i,0]);
		i_ticketOpen = ticketPositionOpenSell(m_magicNumber[i,1],m_names[i,0]);
		if (i_ticketPending>0 && i_ticketOpen>0) { Alert(m_names[i,0],": ERROR - We have two trades in same direction."); }
		else if (i_ticketPending>0 && i_ticketOpen<0) { m_state[i,1] = 1; }
		else if (i_ticketPending<0 && i_ticketOpen>0) { m_state[i,1] = 2; }
		else { m_state[i,1] = 0; }

		// checks
		if (m_state[i,0]>0 && m_state[i,1]>0 && (m_sequence[i,0]!=m_sequence[i,1])) { Alert(m_names[i,0],": The trades have different sequence number."); }
	}
}

// INDICATOR BUFFERS ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   //if (isNewBar || (count == 1)) {
   //if (TimeMinute(TimeCurrent()) != i_minuteLastCalced) {      // repeat every minute not at every tick - EA is for large timeframes
      for(int i=0; i<i_namesNumber; i++) {
	// Once a day at the end of the sleep range calculate today's values
	if (Hour()==StringToInteger(m_names[i,4]) && Minute()==StringToInteger(m_names[i,5])) {
		 // use format 3:23,6:50 given as 3,23,6,50
		 i_SRInMin = (StrToInteger(m_names[i,5]) - StrToInteger(m_names[i,3]))*60 + StrToInteger(m_names[i,4]) - StrToInteger(m_names[i,2]);
		 f_low = 100000;
		 f_high = 0;
		 f_average = 0;
		 for (int ishift=0; ishift<i_SRInMin; ishift++) {
			f_low = MathMin(f_low,iLow(m_names[i,0],PERIOD_M1,ishift));
			f_high = MathMax(f_high,iHigh(m_names[i,0],PERIOD_M1,ishift));
			//f_average = f_average + f_high - f_low;
		 }
		 m_SR[i,0] = f_low;
		 m_SR[i,1] = f_high;
		 //m_averageCandle[i,0] = f_average / (double)i_SRInHours;
		// Then calculate all trade components for the day
		f_SR = m_SR[i,1] - m_SR[i,0]; 
		m_pips[i] = NormalizeDouble(f_SR / MarketInfo(m_names[i][0],MODE_POINT),0);
		f_digits = MarketInfo(m_names[i,0],MODE_DIGITS);
		m_openPrice[i,0] = NormalizeDouble(MarketInfo(m_names[i,0],MODE_ASK) + f_SR,f_digits);
		m_openPrice[i,1] = NormalizeDouble(MarketInfo(m_names[i,0],MODE_BID) - f_SR,f_digits);
		m_stopLoss[i,0] = NormalizeDouble(m_openPrice[i,0] - f_SR,f_digits);
		m_stopLoss[i,1] = NormalizeDouble(m_openPrice[i,1] + f_SR,f_digits);
		m_takeProfit[i,0] = NormalizeDouble(m_openPrice[i,0] + f_SR,f_digits);
		m_takeProfit[i,1] = NormalizeDouble(m_openPrice[i,1] - f_SR,f_digits);
	}
         if (~m_doneForTheDay[i]) {
		 if (Hour()==StringToInteger(m_names[i,4]) && Minute()==StringToInteger(m_names[i,5]) && m_state[i,0]==0 && m_state[i,1]==0) {		// should be the starting point -- open two pending orders
			m_signal[i,0] = 1;		//open pending
			m_signal[i,1] = 1;		// open pending
		 }
		 else if (m_state[i,0]==0 && m_state[i,1]==1) {							// one pending order only, other trade closed, by SL or error in opening pending order. So retry.
			m_signal[i,0] = 1;		// open pending
			m_signal[i,1] = 1;		// delete->open new pending 
		 }
		 else if (m_state[i,0]==1 && m_state[i,1]==0) {							// one pending order only, other trade closed, by SL or error in opening pending order. So retry.
			m_signal[i,0] = 1;		// delete->new open pending
			m_signal[i,1] = 1;		// open pending
		 }
		 else if ((m_state[i,0]==2 && m_state[i,1]==0) || (m_state[i,0]==0 && m_state[i,1]==2)) {	// something wrong
			m_signal[i,0] = -1;		// close trade
			m_signal[i,1] = -1;		// close trade
			Alert("Something is wrong, one trade is open but there is no pending order.");
		 }
		 else if (m_state[i,0]==2 && m_state[i,1]==2) {
			m_signal[i,0] = -1;		// close trade
			m_signal[i,1] = -1;		// close trade
			Alert("Something is wrong, both trades open at the same time.");
		 }
		 else {
			// do nothing - normal operation
			m_signal[i,0] = 0;		
			m_signal[i,1] = 0;		
		 }
	}
	else { // if done for the day, close all open trades
		if (m_state[i,0]>0 || m_state[i,1]>0) {
			m_signal[i,0] = -1;		// close trade
			m_signal[i,1] = -1;		// close trade
		}
	}
      }


// CLOSING TRADE CRITERIA  ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   for(int i=0; i<i_namesNumber; i++) {
		// BUY
         if ((m_signal[i,0]==-1) && StringCompare(m_names[i,1],"Y",false)==0) { 		// close trade
            m_closeBuy[i] = true; 
         }
         else {
            m_closeBuy[i] = false;
         }
		 // SELL
         if ((m_signal[i,1]==-1) && StringCompare(m_names[i,1],"Y",false)==0) { 
            m_closeSell[i] = true; 
         }
         else {
            m_closeSell[i] = false;
         }
         
    }
   
// CLOSING ORDERS //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	for(int i=0; i<i_namesNumber; i++) {
		if (m_closeBuy[i]==true) {
			i_ticket = ticketPositionBuy(m_magicNumber[i,0],m_names[i,0]);
			i_orderType = OrderType();
			if (i_orderType==OP_BUY) {
				success = OrderClose(i_ticket,OrderLots(),MarketInfo(m_names[i,0],MODE_BID),100); }
			else if (i_orderType==OP_BUYLIMIT) {
				success = OrderDelete(i_ticket);
			}
			if (success) { Print("Order closed successfully"); }
			else { Alert("Order #",i_ticket," failed to close with error #", GetLastError()); }
		}
		if (m_closeSell[i]==true) {
			i_ticket = ticketPositionSell(m_magicNumber[i,1],m_names[i,0]);
			i_orderType = OrderType();
			if (i_orderType==OP_SELL) {
				success = OrderClose(i_ticket,OrderLots(),MarketInfo(m_names[i,0],MODE_ASK),100); }
			else if (i_orderType==OP_SELLLIMIT) {
				success = OrderDelete(i_ticket);
			}
			if (success) { Print("Order closed successfully"); }
			else { Alert("Order #",i_ticket," failed to close with error #", GetLastError()); }
		}
    }

/**
// CHECK THAT ORDERS HAVE NOT BEEN CLOSED MANUALLY OR BY SL SINCE LAST TICK /////////////////////////////////////////////////////////////////
   new_ordersHistoryTotal = OrdersHistoryTotal();
   if (new_ordersHistoryTotal - i_ordersHistoryTotal > 0) {         // there is at least one new closed trade
      for(int k=new_ordersHistoryTotal-1; k>=i_ordersHistoryTotal; k--) {        // loop through the latest closed orders
         temp_flag = OrderSelect(k,SELECT_BY_POS,MODE_HISTORY);
         temp_magic = OrderMagicNumber();
         if(temp_flag && ((double)temp_magic/100>i_stratMagicNumber) && ((double)temp_magic/100<i_stratMagicNumber+1)) {    // if closed order belongs to this strategy
            temp_i = -1;
            for(int i=0; i<i_namesNumber; i++) {                                                  // find the row of the product
               if (temp_magic == m_magicNumber[i]) { temp_i = i; }
            }
            if (temp_i < 0) { break; }                                                          // if product not in list traded, exit
            else {
               temp_flag = readLastTradeSubComment(temp_magic,m_names[temp_i,0],true,temp_sequence);        // if in list of products, read the comment
               if (temp_flag) {
                  if (temp_sequence[1] >= 0) {                             // if sequence just ended -> reset
                     m_sequence[temp_i][0] = -1.0;
                     m_sequence[temp_i][1] = 0.0;
                     m_sequence[temp_i][2] = 0.0;
                  }
                  else { m_sequence[temp_i][1] = temp_sequence[1]; }       // if sequence not ended, update cumulative loss
               }
               else {
                  PrintFormat("Cannot read closed trade comment %s",m_names[temp_i,0]);
               }
            }
         }
      }
   }
   i_ordersHistoryTotal = new_ordersHistoryTotal;        // update
            
**/
   
// OPENING/MODIFY TRADING CRITERIA  ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   // no trades on sundays, late and early in the day, earlier stop on fridays
   //if ((TimeHour(TimeCurrent()) >= i_hourStart) && (TimeHour(TimeCurrent()) <= i_hourEnd) && (TimeDayOfWeek(TimeCurrent())!=0) && !((TimeDayOfWeek(TimeCurrent())==5) && (TimeHour(TimeCurrent())>=i_hourEndFriday)))        {    
      for(int i=0; i<i_namesNumber; i++) {
		// BUY
         if ((m_signal[i,0]==1) && StringCompare(m_names[i,1],"Y",false)==0) { 
            m_openBuy[i] = true; 
         }
         else {
            m_openBuy[i] = false;
         }
		 // SELL
         if ((m_signal[i,1]==1) && StringCompare(m_names[i,1],"Y",false)==0) { 
            m_openSell[i] = true; 
         }
         else {
            m_openSell[i] = false;
         }
         
      }
   //}
 
 // ORDER SIZE WARPING //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 /**
 if (b_orderSizeByLabouchere) {         
    for(int i=0; i<i_namesNumber; i++) {
      if ((m_openBuy[i]==true) || (m_openSell[i]==true))  {
         //m_labouchereLosses[i] = labouchereLosses(m_magicNumber[i],m_names[i,0]); 

         //This is actually the martingale betting system capped, Labouchere only leads to more profits if strategy is already profitable under constant bet size
		//Otherwise it leads to magnified losses.  
         m_lots[i] = NormalizeDouble(StrToDouble(m_names[i,xxx]) * m_accountCcyFactors[i] * MathPow(2.0,MathMin(3,(double)m_labouchereLosses[i])),2);
         // Adjust by loss martingale
         //f_weightedLosses = m_sequence[i][1]/(MarketInfo(m_names[i,0],MODE_LOTSIZE)*StrToDouble(m_names[i,3])*StrToDouble(m_names[i,4]));    // sum of losses over stoploss in USD
         //m_lots[i] = MathMax(0.01,NormalizeDouble(((1 - f_weightedLosses) * StrToDouble(m_names[i,3]) * m_accountCcyFactors[i]),2));            // add standard notional to weighted losses
         // This is the proportional system uncapped, the more the consecutive losses, the more the next win has to gain to break even.
         // Capping the losses to a certain number of pips,one can know how big that win has to be to be always profitable 
         //m_lots[i] = NormalizeDouble(StrToDouble(m_names[i,3]) * m_accountCcyFactors[i] * (1 + MathMin(5,(double)m_labouchereLosses[i])),2);
         // This is the breakeven sequence system 
         //int m_breakevenSeq[6]={1,1,2,4,8,16};
         //lots = sizeConst * m_breakevenSeq[MathMin(5,i_labouchereLosses)];
         // This is the (breakeven + 1) sequence system 
         //int m_breakevenSeq[6]={1,1,3,6,12,24};
         //lots = sizeConst * m_breakevenSeq[MathMin(5,i_labouchereLosses)];
      }
    }
 }
**/
 
 // OPENING ORDERS //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   for(int i=0; i<i_namesNumber; i++) {
	// Open Buy
	if (m_openBuy[i]==true) {// && (int)MarketInfo(m_names[i,0],MODE_TRADEALLOWED)>0) {                        // criterion for opening Buy
		// delete existing pending order if there is one
		i_ticketPending = ticketPositionPendingBuy(m_magicNumber[i,0],m_names[i,0]);
		if (i_ticketPending>0) {
			res = OrderDelete(i_ticketPending);
			if (res) { Print("Pending Order deleted successfully"); }
			else { Alert("Order deletion failed with error #", GetLastError()); }
		}
		// open the new pending order
		Print("Attempt to open Buy. Waiting for response..",m_names[i,0],m_magicNumber[i,0]); 
		m_lots[i] = NormalizeDouble(StrToDouble(m_names[i,6]) * m_accountCcyFactors[i] * (1/m_pips[i]) * MathPow(2.0,MathMin(10,1+(double)m_sequence[i,1])),2);
		s_comment = StringConcatenate(IntegerToString(m_magicNumber[i,0]),"_",DoubleToStr(m_sequence[i,0]+1,0));
		i_ticket=OrderSend(m_names[i,0],OP_BUYLIMIT,m_lots[i],m_openPrice[i,0],slippage,m_stopLoss[i,0],m_takeProfit[i,0],s_comment,m_magicNumber[i,0]); //Opening Buy
		Print("OrderSend returned:",i_ticket," Lots: ",m_lots[i]); 
		if (i_ticket < 0)  {                  // Success :)   
			Alert("OrderSend ",m_names[i,0]," failed with error #", GetLastError());
                  	Alert("Open: ",m_openPrice[i,0],". SL: ",m_stopLoss[i,0],". TP: ",m_takeProfit[i,0]);
                  	Alert("Loss#: ",m_sequence[i][1],". SLinUSD: ",StrToDouble(m_names[i,6]),". Factor: ",m_accountCcyFactors[i],". Pips: ",m_pips[i]);
		}
		else {
			m_sequence[i,1] = m_sequence[i,1] + 1;                          // increment trade number
			Alert ("Opened pending order Buy:",i_ticket,",Symbol:",m_names[i,0]," Lots:",m_lots[i]);
		}
	}
	   // Open Sell
	 if (m_openSell[i]==true) {// && (int)MarketInfo(m_names[i,0],MODE_TRADEALLOWED)>0)  {                      // criterion for opening Sell
		// delete existing pending order if there is one
		i_ticketPending = ticketPositionPendingSell(m_magicNumber[i,1],m_names[i,0]);
		if (i_ticketPending>0) {
			res = OrderDelete(i_ticketPending);
			if (res) { Print("Pending Order deleted successfully"); }
			else { Alert("Order deletion failed with error #", GetLastError()); }
		}
		// open the new pending order
		Print("Attempt to open Sell. Waiting for response..",m_names[i,0],m_magicNumber[i,1]); 
	   	m_lots[i] = NormalizeDouble(StrToDouble(m_names[i,6]) * m_accountCcyFactors[i] * (1/m_pips[i]) * MathPow(2.0,MathMin(10,1+(double)m_sequence[i,1])),2);
		s_comment = StringConcatenate(IntegerToString(m_magicNumber[i,1]),"_",DoubleToStr(m_sequence[i,1]+1,0));
	   	i_ticket=OrderSend(m_names[i,0],OP_SELLLIMIT,m_lots[i],m_openPrice[i,1],slippage,m_stopLoss[i,1],m_takeProfit[i,1],s_comment,m_magicNumber[i,1]); //Opening Buy
		Print("OrderSend returned:",i_ticket," Lots: ",m_lots[i]); 
		if (i_ticket < 0)     {                 // Success :)
		  Alert("OrderSend ",m_names[i,0]," failed with error #", GetLastError());
		  Alert("Open: ",m_openPrice[i,1],". SL: ",m_stopLoss[i,1],". TP: ",m_takeProfit[i,1]);
                  Alert("Loss#: ",m_sequence[i][1],". SLinUSD: ",StrToDouble(m_names[i,6]),". Factor: ",m_accountCcyFactors[i],". Pips: ",m_pips[i]);
		}
		else {
		  m_sequence[i,1] = m_sequence[i,1] + 1;                          // increment trade number
		  Alert ("Opened pending order Sell ",i_ticket,",Symbol:",m_names[i,0]," Lots:",m_lots[i]);
	   	}
	}
                                   
        }
    
                  
     
  /**
     
     //Stop EA execution if loss greater than max drawdown.
     if (AccountProfit() < -i_maxDrawdown) {
         lots=0;
     }
     **/
   
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
  } // on timer loop
  
  
  
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
  
  int ticketPositionPendingBuy(int myMagicNumber, string symbol)
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol && (OrderType()==OP_BUYLIMIT || OrderType()==OP_BUYSTOP))
        {
         return OrderTicket();
        }
     }
   return -1;
  }
  
  int ticketPositionPendingSell(int myMagicNumber, string symbol)
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol && (OrderType()==OP_SELLLIMIT || OrderType()==OP_SELLSTOP))
        {
         return OrderTicket();
        }
     }
   return -1;
  }
  
  int ticketPositionOpenBuy(int myMagicNumber, string symbol)
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol && (OrderType()==OP_BUY))
        {
         return OrderTicket();
        }
     }
   return -1;
  }
  
  int ticketPositionOpenSell(int myMagicNumber, string symbol)
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol && (OrderType()==OP_SELL))
        {
         return OrderTicket();
        }
     }
   return -1;
  }
  
  int ticketPositionBuy(int myMagicNumber, string symbol)
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol && (OrderType()==OP_BUYLIMIT || OrderType()==OP_BUY || OrderType()==OP_BUYSTOP))
        {
         return OrderTicket();
        }
     }
   return -1;
  }
  
  int ticketPositionSell(int myMagicNumber, string symbol)
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol && (OrderType()==OP_SELLLIMIT || OrderType()==OP_SELL || OrderType()==OP_SELLSTOP))
        {
         return OrderTicket();
        }
     }
   return -1;
  }
  
  int barLastOpenedTrade(int myMagicNumber, string symbol)
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol && (OrderType()==OP_BUY || OrderType()==OP_SELL) )
        {
         return iBarShift(symbol,timeFrame,OrderOpenTime(),true);
        }
     }
   return -1;
  }
 
  int barLastOpenedTradeHistory(int myMagicNumber, string symbol)
  {
   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol && (OrderType()==OP_BUY || OrderType()==OP_SELL) )
        {
         return iBarShift(symbol,timeFrame,OrderOpenTime(),true);
        }
     }
   return -1;
  }
  
  int barLastClosedTradeHistory(int myMagicNumber, string symbol)
  {
   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol && (OrderType()==OP_BUY || OrderType()==OP_SELL) )
        {
         return iBarShift(symbol,timeFrame,OrderCloseTime(),true);
        }
     }
   return -1;
  }
  
  int dirLastOpenedTrade(int myMagicNumber, string symbol)
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol) {
         if (OrderType()==OP_BUY) { return 1; }
         else if (OrderType()==OP_SELL) { return -1; }
      }
     }
   return 0;
  }
  
  int dirLastOpenedTradeHistory(int myMagicNumber, string symbol)
  {
   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol) {
         if (OrderType()==OP_BUY) { return 1; }
         else if (OrderType()==OP_SELL) { return -1; }
      }
     }
   return 0;
  }
  
  int getName(string s1, string s2)          // gives index
  {
   string temp1 = StringConcatenate(s1,s2);
   string temp2 = StringConcatenate(s2,s1);
   for(int i=0; i<i_namesNumber; i++) {
      if (StringCompare(temp1,StringSubstr(m_names[i][0],0,6),false)==0) { return i; }
      if (StringCompare(temp2,StringSubstr(m_names[i][0],0,6),false)==0) { return i; }
   }
   return -1;
  }
  
  int getMagicNumber(string symbol,int stratMagicNumber)
  {
   for(int i=0; i<i_namesNumber; i++) {
      if (StringCompare(symbol,m_names[i][0],false) == 0) { 
         return stratMagicNumber*100000 + DayOfYear()*100 + (i+1); 
      }
   }
   return 0;
  }
  
  bool readLastTradeComment(int myMagicNumber,string symbol,bool b_searchHistory, double &output[])
  {
   string result[];
   ushort u_sep=StringGetCharacter("_",0);
   int temp;
   ArrayInitialize(output,0);
   if (b_searchHistory) {
      for(int i=OrdersHistoryTotal()-1; i>=0; i--) {
         if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol) {
            temp = StringSplit(OrderComment(),u_sep,result);
            if (ArraySize(result)<2) { PrintFormat("Comment format is wrong for ",symbol); break; }
            output[0] = OrderProfit() + OrderCommission() + OrderSwap();   // profit
            temp = StringFind(result[1],"[");
            if (temp<0) {
               output[1] = StrToDouble(result[1]); } // sequence number
            else if (temp>=0) {
               output[1] = StrToDouble(StringSubstr(result[1],0,temp)); }
            return true;
         }
         else  {
            return false; 
         }
      }
   }
   else {
      for(int i=OrdersTotal()-1; i>=0; i--) {
         if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol) {
            temp = StringSplit(OrderComment(),u_sep,result);
            if (ArraySize(result)<2) { PrintFormat("Comment format is wrong for %s",symbol); break; }
            output[0] = 0.0; //profit
            output[1] = StrToDouble(result[1]);   // sequence number
            return true;
         }
         else  {
            return false; 
         }
      }
   }
   return false;
  }
  
  
  /**
  int labouchereLosses(int myMagicNumber,string symbol)
  {
   int losses = 0;
   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol)
        {
         // if trade loses or win<SL, count it as a loss. But only increment counter if trade <0. If 0<trade<SL, dont reset counter, ie counter resets only if win>SL 
         if ((OrderClosePrice() < OrderOpenPrice() + stopLoss*Point) && OrderType()==OP_BUY) { 
            if (OrderProfit() + OrderCommission() + OrderSwap() < 0) { losses++; }              // 
         }                                                                                      
         else if ((OrderClosePrice() > OrderOpenPrice() - stopLoss*Point) && OrderType()==OP_SELL) { 
            if (OrderProfit() + OrderCommission() + OrderSwap() < 0) { losses++; }
         }
         else { return losses; }
        }
      //Print(losses);
     }
   return losses;
  }
  **/
  
  int labouchereLosses(int myMagicNumber,string symbol)
  {
   int losses = 0, open_iPrev=0, close_iPrev=0,open_i=-1, close_i=-1;
   double cumLoss = 0.0;
   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol)
        {
         open_i = iBarShift(symbol,timeFrame,OrderOpenTime(),true);
         close_i = iBarShift(symbol,timeFrame,OrderCloseTime(),true);
         if (open_i<0 || close_i<0) { Print("Trade history has wrong open or close times"); }
         
         if (close_i-open_iPrev<100) {     // Consider move after 100 bars as over. start new
            //cumLoss = cumLoss + ;
            if (OrderProfit() + OrderCommission() + OrderSwap() < 0) { losses++; }
            else { return losses; }
         }
         else { return losses; }
         open_iPrev = open_i;
        }
      //Print(losses);
      //close_iPrev = close_i;
     }
   return losses;
  }
  
  double labouchereLossesUSD(int myMagicNumber,string symbol)
  {
   double lossUSD = 0.0; 
   int open_iPrev=0, close_iPrev=0,open_i=-1, close_i=-1;
   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol)
        {
         open_i = iBarShift(symbol,timeFrame,OrderOpenTime(),true);
         close_i = iBarShift(symbol,timeFrame,OrderCloseTime(),true);
         if (open_i<0 || close_i<0) { Print("Trade history has wrong open or close times"); }
         
         if (close_i-open_iPrev<100) {     // Consider move after 100 bars as over. start new
            if (OrderProfit() + OrderCommission() + OrderSwap() < 0) { 
               lossUSD = lossUSD + OrderProfit(); }
            else { return -lossUSD; }
         }
         else { return -lossUSD; }
         open_iPrev = open_i;
        }
      //Print(losses);
      //close_iPrev = close_i;
     }
   return -lossUSD;
  }
  
  int labouchereLossesFirstBarInSequence(int myMagicNumber,string symbol)
  {
   int ibar = -1; 
   int open_iPrev=0, close_iPrev=0,open_i=-1, close_i=-1;
   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol)
        {
         open_i = iBarShift(symbol,timeFrame,OrderOpenTime(),true);
         close_i = iBarShift(symbol,timeFrame,OrderCloseTime(),true);
         if (open_i<0 || close_i<0) { Print("Trade history has wrong open or close times"); }
         
         if (close_i-open_iPrev<100) {     // Consider move after 100 bars as over. start new
            if (OrderProfit() + OrderCommission() + OrderSwap() < 0) { 
               ibar = open_i; }
            else { return ibar; }
         }
         else { return ibar; }
         open_iPrev = open_i;
        }
      //Print(losses);
      //close_iPrev = close_i;
     }
   return ibar;
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
