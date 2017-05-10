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
bool b_long = true;
bool b_short = true;
input bool b_VWAP = true;
input bool b_noNewSequence = false;
input string s_inputFileName = "TF_DEMO_H1_100_5_BOLLINGER.txt"; 
bool b_lockIn = true;
//bool b_trailingSL = false;
bool b_orderSizeByLabouchere = true;
//bool b_safetyFactor = false;
//bool b_writeToFile = false;
bool b_sendEmail=false;
input int i_stratMagicNumber = 34;    // Always positive
// if 0,23 it trades nonstop
int const i_hourStart = 0;       
int const i_hourEnd = 23;
int const i_hourEndFriday = 23;
input double const f_deviationPerc = 2.5;
// sinewave
//int sinewave_duration = 300;   
//int sinewave_superSmootherMemory = 80;
// filter 
//input int filter_cutoff = 10;
input int i_mode = 3; // 1:VWAP 2:MA, 3:BOLLINGER
bool filter_supersmoother = true;
// trading system safety factor
//int i_windowLength = 20;
//double f_safetyThreshold = 1.0;

// TRADE ACCOUNTING VARIABLES ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
int const slippage =10;           // in points
//double const b_commission = 6*Point+10*Point;  // commission + safety net
//int const i_maxDrawdown = 10000;      // in USD max drawdown
int const timeFrame=Period();        
int count = 0,i_trade=0,i_previousVWAPZone=0,i_currentVWAPZone=0,i_labouchereLossesFirstBarInSequence=0,i_namesNumber=0;
bool Work = true;             //EA will work
string const symb =Symbol();
//double f_accountBalancePrev=0,f_sigmaY=0,f_sigmaX=0,f_meanY=0,f_meanX=0,f_safetyCounter=0;
//double f_labouchereAccBalancePrev=0;
int m_barLastOpenedTrade[NAMESNUMBERMAX];
int m_barLastOpenedTradeHistory[NAMESNUMBERMAX];
int m_myMagicNumber[NAMESNUMBERMAX];  // Magic Numbers
double m_lots[NAMESNUMBERMAX];
double m_accountCcyFactors[NAMESNUMBERMAX];
double m_sequence[NAMESNUMBERMAX][3];     // VWAP,Cum Losses excl current,current trade number
string m_names[NAMESNUMBERMAX];
double m_bollingerDeviationInPips[];
bool m_tradeFlag[];
double m_filter[][2];      // vwap,filter freq
double m_profitInUSD[];

// OTHER VARIABLES //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//int directionLastOpenedTrade=0; // 0:no trade yet, 1: buy, -1:sell
int h;
int i_labouchereLosses=0;
double temp_sequence[4];
int i_ordersHistoryTotal=OrdersHistoryTotal();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   
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
   ArrayInitialize(m_barLastOpenedTrade,-1);
   ArrayInitialize(m_barLastOpenedTradeHistory,-1);
   ArrayInitialize(m_sequence,0.0);
   ArrayInitialize(m_myMagicNumber,0);
   ArrayInitialize(m_lots,0.0);
   ArrayInitialize(m_accountCcyFactors,0.0);
   ArrayInitialize(m_bollingerDeviationInPips,0);
   ArrayInitialize(m_tradeFlag,false);
   ArrayInitialize(m_filter,0.0);
   ArrayInitialize(m_profitInUSD,0.0);
   // Resize arrays once number of products known
   ArrayResize(m_names,i_namesNumber,0);
   ArrayResize(m_barLastOpenedTrade,i_namesNumber,0);
   ArrayResize(m_barLastOpenedTradeHistory,i_namesNumber,0);
   ArrayResize(m_sequence,i_namesNumber,0);
   ArrayResize(m_myMagicNumber,i_namesNumber,0);
   ArrayResize(m_lots,i_namesNumber,0);
   ArrayResize(m_accountCcyFactors,i_namesNumber,0);
   ArrayResize(m_bollingerDeviationInPips,i_namesNumber,0);
   ArrayResize(m_tradeFlag,i_namesNumber,0);
   ArrayResize(m_filter,i_namesNumber,0);
   ArrayResize(m_profitInUSD,i_namesNumber,0);
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
         //for (int j=0; j<ArraySize(m_rows); j++) {
         //   m_names[i][j] = m_rows[j];
         //}
      }
      else { PrintFormat("Failed to read row number %d, Number of elements read = %d instead of %d",i,temp,ArraySize(m_rows)); }
      // magic numbers
      m_myMagicNumber[i] = getMagicNumber(m_names[i],i_stratMagicNumber);
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
      if (StringCompare(StringSubstr(m_names[i],0,3),AccountCurrency(),false)==0) {
          if (StringCompare(StringSubstr(m_names[i],3,3),"JPY",false)==0) {
              m_accountCcyFactors[i] = 100 / MarketInfo(m_names[i],MODE_BID); }
          else { m_accountCcyFactors[i] = 1.0 / MarketInfo(m_names[i],MODE_BID); }
      }
      else if (StringCompare(StringSubstr(m_names[i],3,3),AccountCurrency(),false)==0) {
              m_accountCcyFactors[i] = 1.0; }
      else if (StringCompare(StringSubstr(m_names[i],0,3),"WTI",false)==0) {
            m_accountCcyFactors[i] = 10.0; 
         }
      else { 
         int k = getName(StringSubstr(m_names[i],3,3),"USD");
         if (k>=0) {
            if (StringFind(m_names[k],"USD")==0) {
               if (StringFind(m_names[k],"USDJPY")>=0) {
                  m_accountCcyFactors[i] = 100 / MarketInfo(m_names[k],MODE_BID); }
               else {
                  m_accountCcyFactors[i] = 1.0 / MarketInfo(m_names[k],MODE_BID); }
            }
            else if (StringFind(m_names[k],"USD")==3) {
               m_accountCcyFactors[i] = MarketInfo(m_names[k],MODE_BID); } 
         } 
         else {
            m_accountCcyFactors[i] = 1.0;       // not a currency
         }
      }
      // initialize m_sequence  
      m_sequence[i][0] = -1.0;      //Initialize to -1,0,0      
      if (isPositionOpen(m_myMagicNumber[i],m_names[i])) {                                                       // check if trade open
         if (readLastTradeSubComment(m_myMagicNumber[i],m_names[i],false,temp_sequence)) {
            for (int j=0;j<3;j++) {
               m_sequence[i][j] = temp_sequence[j];
            }
            m_bollingerDeviationInPips[i] = NormalizeDouble((1/MarketInfo(m_names[i],MODE_POINT)) * MathAbs(OrderOpenPrice()-OrderStopLoss()),0);
         }
         else { PrintFormat("Cannot read open trade comment %s",m_names[i]); }
      }
      else {                                                                                                          // if not open check in closed trades
         if (readLastTradeSubComment(m_myMagicNumber[i],m_names[i],true,temp_sequence)) {
            if (temp_sequence[1]>=0) {                  // sequence ended
               m_sequence[i][0] = -1.0;
               m_sequence[i][1] = 0.0;
               m_sequence[i][2] = 0.0;
            }
            else if (temp_sequence[1]<0 && temp_sequence[3]<2400) {          // sequence not ended but no new position for less than XXX bars, likely a stoploss
               for (int j=0;j<3;j++) {
                  m_sequence[i][j] = temp_sequence[j];
               }
               m_bollingerDeviationInPips[i] = NormalizeDouble((1/MarketInfo(m_names[i],MODE_POINT)) * MathAbs(OrderOpenPrice()-OrderStopLoss()),0);
            }
            else {                                                         // sequence not ended but no new position for more than XXX bars, likely a stoploss, continue sequence but reset VWAP
               m_sequence[i][0] = -1.0;                                    // reset VWAP
               m_sequence[i][1] = temp_sequence[1];
               m_sequence[i][2] = temp_sequence[2];
               m_bollingerDeviationInPips[i] = NormalizeDouble((1/MarketInfo(m_names[i],MODE_POINT)) * MathAbs(OrderOpenPrice()-OrderStopLoss()),0);
            }
         }
         else { PrintFormat("Cannot read closed trade comment %s",m_names[i]); }
      }
      //Print(m_sequence[i][0],"_",m_sequence[i][1],"_",m_sequence[i][2]);
      
   }
   
   Alert ("Function init() triggered at start for ",symb);// Alert
   if (IsDemo() == false) { Alert("THIS IS NOT A DEMO RUN"); }
   
   //f_accountBalancePrev = AccountBalance();
   //f_labouchereAccBalancePrev = AccountBalance();
   
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
   ticket,temp_signal,new_ordersHistoryTotal,temp_i,temp_magic,
   i_orderMagicNumber,
   i_win=0,i_loss=0;
   bool res,isNewBar,temp_flag;
   double
   f_winPerc=0,f_zeroCurveDiff=0,temp_vwap=-1.0,
   f_weightedLosses = 0.0,
   f_enterValue1=0.0,f_vol=0.0,
   SL,TP,BID,ASK,f_central,f_band,
   f_avgWin = 0, f_avgLoss = 0,
   f_orderOpenPrice,f_orderStopLoss,
   f_filterPrev = 0,f_filter = 0,temp_T1=0,f_VWAP=0;
   int m_signal[]; 
   bool m_openBuy[];
   bool m_openSell[];
   bool m_closeBuy[];
   bool m_closeSell[];
   bool m_isPositionOpen[];
   int m_ticketPositionPending[];
   double m_orderLots[];
   double m_VWAP[];
   int m_orderTickets[];
   string s_comment,s_orderSymbol;
   
// PRELIMINARY PROCESSING ///////////////////////////////////////////////////////////////////////////////////////////////////////////
   ArrayResize(m_signal,i_namesNumber,0);
   ArrayResize(m_openBuy,i_namesNumber,0);
   ArrayResize(m_openSell,i_namesNumber,0);
   ArrayResize(m_closeBuy,i_namesNumber,0);
   ArrayResize(m_closeSell,i_namesNumber,0);
   ArrayResize(m_isPositionOpen,i_namesNumber,0);
   ArrayResize(m_ticketPositionPending,i_namesNumber,0);
   ArrayResize(m_orderLots,i_namesNumber,0);
   ArrayResize(m_VWAP,i_namesNumber,0);
   ArrayResize(m_orderTickets,i_namesNumber,0);
   ArrayInitialize(m_signal,0);
   ArrayInitialize(m_openBuy,false);
   ArrayInitialize(m_openSell,false);
   ArrayInitialize(m_closeBuy,false);
   ArrayInitialize(m_closeSell,false);
   ArrayInitialize(m_isPositionOpen,false);
   ArrayInitialize(m_ticketPositionPending,-1);
   ArrayInitialize(m_orderLots,0);
   ArrayInitialize(m_VWAP,0);
   ArrayInitialize(m_orderTickets,0);
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
      

            

// INDICATOR BUFFERS ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   //if (isNewBar || (count == 1)) {
   //if (TimeMinute(TimeCurrent()) != i_minuteLastCalced) {      // repeat every minute not at every tick - EA is for large timeframes
      for(int i=0; i<i_namesNumber; i++) {
      if (m_tradeFlag[i]==true) {
         if (b_VWAP) {
            if (true) { // use constant vwap for sequence
               temp_T1 = iCustom(m_names[i],0,"petousis_VWAPsignal",m_filter[i][0],m_filter[i][1],i_mode,filter_supersmoother,false,f_deviationPerc,1000,m_sequence[i][0],3,1);
               m_VWAP[i] = iCustom(m_names[i],0,"petousis_VWAPsignal",m_filter[i][0],m_filter[i][1],i_mode,filter_supersmoother,false,f_deviationPerc,1000,m_sequence[i][0],2,1);       //needed at every tick
            }
            else {      // use varying vwap
               temp_T1 = iCustom(m_names[i],0,"petousis_VWAPsignal",m_filter[i][0],m_filter[i][1],i_mode,filter_supersmoother,false,f_deviationPerc,1000,-1,3,1);
               m_VWAP[i] = iCustom(m_names[i],0,"petousis_VWAPsignal",m_filter[i][0],m_filter[i][1],i_mode,filter_supersmoother,false,f_deviationPerc,1000,-1,2,1);       //needed at every tick
            }
         }
         else {
            temp_T1 = iCustom(m_names[i],0,"petousis_SuperSmootherSignal",m_filter[i][0],m_filter[i][1],filter_supersmoother,false,f_deviationPerc,1000,3,1);
            m_VWAP[i] = iCustom(m_names[i],0,"petousis_SuperSmootherSignal",m_filter[i][0],m_filter[i][1],filter_supersmoother,false,f_deviationPerc,1000,4,1);       //needed at every tick
         }
         //m_sinewave[i] = (int)iCustom(m_names[i,0],0,"petousis_sinewave",sinewave_duration,sinewave_superSmootherMemory,3,1,1000,4,1);       //needed at every tick
         
         if (temp_T1 > 0.001) {              // previous
            if (m_sequence[i][2]<1) {         // new sequence, so update the pips
              f_central = iCustom(m_names[i],0,"petousis_VWAPsignal",m_filter[i][0],m_filter[i][1],3,filter_supersmoother,false,f_deviationPerc,1000,-1,4,1);
              f_band = iCustom(m_names[i],0,"petousis_VWAPsignal",m_filter[i][0],m_filter[i][1],3,filter_supersmoother,false,f_deviationPerc,1000,-1,2,1);
              m_bollingerDeviationInPips[i] = NormalizeDouble((1/MarketInfo(m_names[i],MODE_POINT)) * MathAbs(f_band-f_central),0);
            }
            if (temp_T1 > m_VWAP[i]) {
               m_signal[i] = 1;
            }
            else if (temp_T1 < m_VWAP[i]) {
               m_signal[i] = -1;
            }
            else {
               m_signal[i] = 0;
            }}
         else {
            m_signal[i] = 0;
         }
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
/**
   for(int i=0; i<i_namesNumber; i++) {
   
   total=OrdersTotal();                                     // Amount of orders
   ticket = OrderTicket();
   orderType = OrderType();
   orderOpenPrice = OrderOpenPrice();
   orderStopLoss = OrderStopLoss();
   orderTakeProfit = OrderTakeProfit();
   orderLots = OrderLots();
   //TRAILING STOP LOSS & TAKE PROFIT & LOCKIN
   if (isPositionOpen && OrderCloseTime()==0) {
      if (orderType==OP_BUY) {                //buy
         // LOCKIN
         if (b_lockIn && (orderStopLoss<orderOpenPrice)) {        
            if (Bid-orderOpenPrice>f_lockIn*Point) {   // lockin trailing can dependent on volatility
               if (orderStopLoss < orderOpenPrice + b_commission) {
                  res = OrderModify(ticket,orderOpenPrice,orderOpenPrice + b_commission,orderTakeProfit,0,Blue);
                  if (!res) {
                     Alert("Error in OrderModify. Error code=", GetLastError(),symb);
                     if (symb=="SPX500") {
                        Alert("point is:",Point," stoploss:",orderOpenPrice + b_commission);
                     }
                  }
                  else {
                     Alert("Order modified successfully.");
                  }
               }
            }
         }
         // TRAILING STOP LOSS
         if (b_trailingSL) {
            if (Bid-orderOpenPrice>f_trailingSL*Point) {
               trailingStop = Bid - f_trailingSL*Point + b_commission;
               orderStopLoss = OrderStopLoss();
               if (orderStopLoss<trailingStop) {
                  res = OrderModify(ticket,orderOpenPrice,trailingStop,orderTakeProfit,0,Blue);
                  if (!res) {
                     Alert("Error in OrderModify. Error code=", GetLastError(),symb);
                  }
                  else {
                     Alert("Order modified successfully.");
                  }
               }
            }
         }
         
      
   **/

// CLOSING TRADE CRITERIA  ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   for(int i=0; i<i_namesNumber; i++) {
   if (m_tradeFlag[i]==true) {
      if (m_signal[i] != 0) {
         m_isPositionOpen[i]=isPositionOpen(m_myMagicNumber[i],m_names[i]);
         if (m_isPositionOpen[i]) {
            if ((m_signal[i] < 0) && OrderType()==OP_BUY) {
               m_closeBuy[i]=true;
               m_orderLots[i] = OrderLots();
               m_orderTickets[i] = OrderTicket();
            }                   // CLOSE trade if get opposite signal, use T1 signal to avoid false knockouts
            else if ((m_signal[i] >0) && OrderType()==OP_SELL) {
               m_closeSell[i]=true;
               m_orderLots[i] = OrderLots();
               m_orderTickets[i] = OrderTicket();
            }
         }     
      }
      /**
      if (m_sinewave[i] != 0) {
         m_isPositionOpen[i]=isPositionOpen(m_myMagicNumber[i],m_names[i,0]);
         if (m_isPositionOpen[i]) {
            if ((m_sinewave[i] < 0) && OrderType()==OP_BUY) {
               m_closeBuy[i]=true;
               m_orderLots[i] = OrderLots();
               m_orderTickets[i] = OrderTicket();
            }                   // CLOSE trade if get opposite signal, use T1 signal to avoid false knockouts
            else if ((m_sinewave[i] >0) && OrderType()==OP_SELL) {
               m_closeSell[i]=true;
               m_orderLots[i] = OrderLots();
               m_orderTickets[i] = OrderTicket();
            }
         }     
      }
      **/
   }
   }
   
// CLOSING ORDERS //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 
 for(int i=0; i<i_namesNumber; i++) {
 if (m_tradeFlag[i]==true) {
      if (m_closeBuy[i]==true) {
         m_barLastOpenedTrade[i] = barLastOpenedTrade(m_myMagicNumber[i],m_names[i]);
         if (m_isPositionOpen[i] && m_barLastOpenedTrade[i]!=0) {
            RefreshRates();
            Alert("Attempt to close Buy ",m_orderTickets[i]); 
            res = OrderClose(m_orderTickets[i],m_orderLots[i],MarketInfo(m_names[i],MODE_BID),100);          // slippage 100, so it always closes
            if (res==true) {
               Alert("Order Buy closed."); 
               Sleep(2000);              // wait a bit to open new trade
               if (readLastTradeSubComment(m_myMagicNumber[i],m_names[i],true,temp_sequence)) {
                  if (temp_sequence[1] >= 0) {            // sequence just ended
                     m_sequence[i][0] = -1.0;
                     m_sequence[i][1] = 0.0;
                     m_sequence[i][2] = 0.0;
                  }
                  else { m_sequence[i][1] = temp_sequence[1]; }
                  i_ordersHistoryTotal = OrdersHistoryTotal();
               }
               else { PrintFormat("Cannot read closed trade comment %s",m_names[i]); }
               break;
            }
            if (Fun_Error(GetLastError())==1) {
               continue;
            }
            return;
         }
      }
      if (m_closeSell[i]==true) {
         m_barLastOpenedTrade[i] = barLastOpenedTrade(m_myMagicNumber[i],m_names[i]);
         if ( m_isPositionOpen[i] && m_barLastOpenedTrade[i]!=0) {
            RefreshRates();
            Alert("Attempt to close Sell ",m_orderTickets[i]); 
            res = OrderClose(m_orderTickets[i],m_orderLots[i],MarketInfo(m_names[i],MODE_ASK),100);
            if (res==true) {
               Alert("Order Sell closed. "); 
               Sleep(2000);              // wait a bit to open new trade
               if (readLastTradeSubComment(m_myMagicNumber[i],m_names[i],true,temp_sequence)) {
                  if (temp_sequence[1] >= 0) {            // sequence just ended
                     m_sequence[i][0] = -1.0;
                     m_sequence[i][1] = 0.0;
                     m_sequence[i][2] = 0.0;
                  }
                  else { m_sequence[i][1] = temp_sequence[1]; }
                  i_ordersHistoryTotal = OrdersHistoryTotal();
               }
               else { PrintFormat("Cannot read closed trade comment %s",m_names[i]); }
               
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

// CHECK THAT ORDERS HAVE NOT BEEN CLOSED MANUALLY OR BY SL SINCE LAST TICK /////////////////////////////////////////////////////////////////
   new_ordersHistoryTotal = OrdersHistoryTotal();
   if (new_ordersHistoryTotal - i_ordersHistoryTotal > 0) {         // there is at least one new closed trade
      for(int k=new_ordersHistoryTotal-1; k>=i_ordersHistoryTotal; k--) {        // loop through the latest closed orders
         temp_flag = OrderSelect(k,SELECT_BY_POS,MODE_HISTORY);
         temp_magic = OrderMagicNumber();
         if(temp_flag && ((double)temp_magic/100>i_stratMagicNumber) && ((double)temp_magic/100<i_stratMagicNumber+1)) {    // if closed order belongs to this strategy
            temp_i = -1;
            for(int i=0; i<i_namesNumber; i++) {                                                  // find the row of the product
               if (temp_magic == m_myMagicNumber[i]) { temp_i = i; }
            }
            if (temp_i < 0) { break; }                                                          // if product not in list traded, exit
            else {
               temp_flag = readLastTradeSubComment(temp_magic,m_names[temp_i],true,temp_sequence);        // if in list of products, read the comment
               if (temp_flag) {
                  if (temp_sequence[1] >= 0) {                             // if sequence just ended -> reset
                     m_sequence[temp_i][0] = -1.0;
                     m_sequence[temp_i][1] = 0.0;
                     m_sequence[temp_i][2] = 0.0;
                  }
                  else { m_sequence[temp_i][1] = temp_sequence[1]; }       // if sequence not ended, update cumulative loss
               }
               else {
                  PrintFormat("Cannot read closed trade comment %s",m_names[temp_i]);
               }
            }
         }
      }
   }
   i_ordersHistoryTotal = new_ordersHistoryTotal;        // update
   
   
// OPENING TRADING CRITERIA  ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   // no trades on sundays, late and early in the day, earlier stop on fridays
   //if ((TimeHour(TimeCurrent()) >= i_hourStart) && (TimeHour(TimeCurrent()) <= i_hourEnd) && (TimeDayOfWeek(TimeCurrent())!=0) && !((TimeDayOfWeek(TimeCurrent())==5) && (TimeHour(TimeCurrent())>=i_hourEndFriday)))        {    
      for(int i=0; i<i_namesNumber; i++) {
      if (m_tradeFlag[i]==true) {
         // open signal when crossing happened current or last bar.
         temp_signal = m_signal[i];
         if ((temp_signal >0) && b_long){ 
            m_openBuy[i] = true; 
            //Print("indicator Buy signal"); 
         }
         else if ((temp_signal <0) && b_short){ 
            m_openSell[i] = true; 
            //Print("indicator Sell signal"); 
         }
         else {
            m_openBuy[i] = false;
            m_openSell[i] = false;
         }
         
         // Additional conditions on firing signals
         if (m_openBuy[i]==true)  {                            
            m_isPositionOpen[i]=isPositionOpen(m_myMagicNumber[i],m_names[i]);
            if (m_isPositionOpen[i]==true) { m_openBuy[i]=false; }      // dont buy if position already open
            else {
               m_barLastOpenedTradeHistory[i] = barLastOpenedTradeHistory(m_myMagicNumber[i],m_names[i]);
               if (m_barLastOpenedTradeHistory[i]==0) { m_openBuy[i]=false; }        // or position opened and closed already in current bar
            }
         }
         if (m_openSell[i]==true)  {                            
            m_isPositionOpen[i]=isPositionOpen(m_myMagicNumber[i],m_names[i]);
            if (m_isPositionOpen[i]==true) { m_openSell[i]=false; }
            else {
               m_barLastOpenedTradeHistory[i] = barLastOpenedTradeHistory(m_myMagicNumber[i],m_names[i]);
               if (m_barLastOpenedTradeHistory[i]==0) { m_openSell[i]=false; }  
            } 
         }
      }
      }
   //}
 
 // ORDER SIZE WARPING //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 /**
 if (b_orderSizeByVol) {
    if (openBuy || openSell) {
      if (f_vol>f_highVolThreshold) {
         lots = sizeConst * f_highVolFactor;
      }
      else if (f_vol<f_lowVolThreshold) {
         lots = sizeConst * f_lowVolFactor;
      }
      else { lots = sizeConst * f_midVolFactor; }
    }
 }
 **/
 /**
 if (b_orderSizeByLabouchere) {         
    for(int i=0; i<i_namesNumber; i++) {
      if ((m_openBuy[i]==true) || (m_openSell[i]==true))  {
         //m_labouchereLosses[i] = labouchereLosses(m_myMagicNumber[i],m_names[i,0]); 

         //This is actually the martingale betting system capped, Labouchere only leads to more profits if strategy is already profitable under constant bet size
         //Otherwise it leads to magnified losses.  
         //m_lots[i] = NormalizeDouble(StrToDouble(m_names[i,3]) * m_accountCcyFactors[i] * MathPow(2.0,MathMin(3,(double)m_labouchereLosses[i])),2);
         // Adjust by loss martingale
         f_weightedLosses = m_sequence[i][1]/(MarketInfo(m_names[i,0],MODE_LOTSIZE)*StrToDouble(m_names[i,3])*StrToDouble(m_names[i,4]));    // sum of losses over stoploss in USD
         m_lots[i] = MathMax(0.01,NormalizeDouble(((1 - f_weightedLosses) * StrToDouble(m_names[i,3]) * m_accountCcyFactors[i]),2));            // add standard notional to weighted losses
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
   if (m_tradeFlag[i]==true) {
      if (((m_openBuy[i]==true) || (m_openSell[i]==true)) && !(b_noNewSequence && m_sequence[i][0]<0))                             // Send order when receive buy or sell signal
        {
         m_isPositionOpen[i]=isPositionOpen(m_myMagicNumber[i],m_names[i]);
         m_ticketPositionPending[i]=ticketPositionPending(m_myMagicNumber[i],m_names[i]);
         // Delete preemptive order if it exists pending but there a buy/sell signal
         if (OrderSelect(m_ticketPositionPending[i],SELECT_BY_TICKET,MODE_TRADES) && (OrderType()==OP_BUYSTOP || OrderType()==OP_SELLSTOP)) {
            res = OrderDelete(m_ticketPositionPending[i]);           // delete pending
            if (res) { Print(m_names[i],"_Preemptive Order deleted successfully, because there was a buy/sell signal"); }
            else { Alert(m_names[i],"_Preemptive Order deletion failed. There is a buy/sell signal"); }
         }
         // Open Buy
         if (m_openBuy[i]==true) // && (int)MarketInfo(m_names[i,0],MODE_TRADEALLOWED)>0) 
           {                                       // criterion for opening Buy
            //RefreshRates();                        // Refresh rates
            //BID = MarketInfo(m_names[i],MODE_BID);
            ASK = MarketInfo(m_names[i],MODE_ASK);
            SL=NormalizeDouble(ASK - m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));     // Calculating SL of opened
            TP=NormalizeDouble(ASK + m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));   // Calculating TP of opened
            m_lots[i] = MathMax(0.01,NormalizeDouble((-m_sequence[i][1]+m_profitInUSD[i]) / m_accountCcyFactors[i] / m_bollingerDeviationInPips[i],2));
            Print("Attempt to open Buy ",m_lots[i]," of ",m_names[i],". Waiting for response.. Magic Number: ",m_myMagicNumber[i]); 
            if (m_ticketPositionPending[i]<0 && m_isPositionOpen[i]==false) {       // if no position and no pending -> send pending order
               if (m_sequence[i][0] < 0) { temp_vwap = m_VWAP[i]; } else { temp_vwap = m_sequence[i][0]; }
               s_comment = StringConcatenate(IntegerToString(m_myMagicNumber[i]),"_",DoubleToStr(temp_vwap,5),"_",DoubleToStr(m_sequence[i][1],2),"_",DoubleToStr(m_sequence[i][2]+1,0));
               ticket=OrderSend(m_names[i],OP_BUYLIMIT,m_lots[i],ASK,slippage,SL,TP,s_comment,m_myMagicNumber[i]); //Opening Buy
               Print("OrderSend returned:",ticket," Lots: ",m_lots[i]); 
               if (ticket < 0)  {                  // Success :)   
                  Alert("OrderSend failed with error #", GetLastError());
                  Alert("Ask: ",ASK,". SL: ",SL,". TP: ",TP);
                  Alert("Loss: ",m_sequence[i][1],". SLinUSD: ",m_profitInUSD[i],". Factor: ",m_accountCcyFactors[i],". Pips: ",m_bollingerDeviationInPips[i]);
               }
               else {
                  if (m_sequence[i][0] < 0) { m_sequence[i][0] = m_VWAP[i]; }       // update vwap if new sequence
                  m_sequence[i][2] = m_sequence[i][2] + 1;                          // increment trade number
                  Alert ("Opened pending order Buy:",ticket,",Symbol:",m_names[i]," Lots:",m_lots[i]);
                  //PlaySound("bikehorn.wav");
                  if (b_sendEmail) { 
                     res = SendMail("VWAP TRADE ALERT","Algo bought "+m_names[i]+" "+DoubleToStr(Period(),0)); 
                     if (res==false) { Alert(m_names[i]+" "+DoubleToStr(Period(),0)," Email could not be sent.");  }
                  }
               }
            }
            else if (m_ticketPositionPending[i]>0) {     // if pending order exists -> modify pending order
               res = OrderModify(m_ticketPositionPending[i],ASK,SL,TP,0);
               if (res) { Print("Order modified successfully:",m_names[i]); }
               else { Alert(m_names[i],": Order modification failed with error #", GetLastError()); }
            }
            else { Alert("ERROR - ",m_names[i]," System is sending a buy order, but it is neither opening nor modifying."); }
           }
           // Open Sell
         if (m_openSell[i]==true) // && (int)MarketInfo(m_names[i,0],MODE_TRADEALLOWED)>0) 
           {                                       // criterion for opening Sell
            //RefreshRates();                        // Refresh rates
            BID = MarketInfo(m_names[i],MODE_BID);
            //ASK = MarketInfo(m_names[i],MODE_ASK);
            SL=NormalizeDouble(BID + m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));     // Calculating SL of opened
            TP=NormalizeDouble(BID - m_bollingerDeviationInPips[i]*MarketInfo(m_names[i],MODE_POINT),(int)MarketInfo(m_names[i],MODE_DIGITS));   // Calculating TP of opened
            m_lots[i] = MathMax(0.01,NormalizeDouble((-m_sequence[i][1]+m_profitInUSD[i]) / m_accountCcyFactors[i] / m_bollingerDeviationInPips[i],2));
            Print("Attempt to open Sell ",m_lots[i]," of ",m_names[i],". Waiting for response.. Magic Number: ",m_myMagicNumber[i]);
            if (m_ticketPositionPending[i]<0 && m_isPositionOpen[i]==false) {
               if (m_sequence[i][0] < 0) { temp_vwap = m_VWAP[i]; } else { temp_vwap = m_sequence[i][0]; }
               s_comment = StringConcatenate(IntegerToString(m_myMagicNumber[i]),"_",DoubleToStr(temp_vwap,5),"_",DoubleToStr(m_sequence[i][1],2),"_",DoubleToStr(m_sequence[i][2]+1,0));
               ticket=OrderSend(m_names[i],OP_SELLLIMIT,m_lots[i],BID,slippage,SL,TP,s_comment,m_myMagicNumber[i]); //Opening Sell
               Print("OrderSend returned:",ticket," Lots: ",m_lots[i]); 
               if (ticket < 0)     {                 // Success :)
                  Alert("OrderSend failed with error #", GetLastError());
                  Alert("Bid: ",BID,". SL: ",SL,". TP: ",TP);
                  Alert("Loss: ",m_sequence[i][1],". SLinUSD: ",m_profitInUSD[i],". Factor: ",m_accountCcyFactors[i],". Pips: ",m_bollingerDeviationInPips[i]);
               }
               else {
                  if (m_sequence[i][0] < 0) { m_sequence[i][0] = m_VWAP[i]; }       // update vwap if new sequence
                  m_sequence[i][2] = m_sequence[i][2] + 1;                          // increment trade number
                  Alert ("Opened pending order Sell ",ticket,",Symbol:",m_names[i]," Lots:",m_lots[i]);
                  PlaySound("bikehorn.wav");
                  if (b_sendEmail) { 
                     res = SendMail("VWAP TRADE ALERT","Algo sold "+m_names[i]+" "+DoubleToStr(Period(),0)); 
                     if (res==false) { Alert(m_names[i]+" "+DoubleToStr(Period(),0)," Email could not be sent.");  }
                  }
               }
            }
            else if (m_ticketPositionPending[i]>0) {
               res = OrderModify(m_ticketPositionPending[i],BID,SL,TP,0);
               if (res) { Print("Order modified successfully:",m_names[i]); }
               else { Alert(m_names[i],": Order modification failed with error #", GetLastError()); }
               }
            else { Alert("ERROR - ",m_names[i]," System is sending a sell order, but it is neither opening nor modifying."); }
           }                                
        }
    }
    }
                  
     
  // SYSTEM SAFETY //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////   
     /**
     // trading system safety
     if ((MathAbs(AccountBalance()-f_accountBalancePrev) > 0.001) && b_safetyFactor) {
         // initialize
         i_order = OrdersHistoryTotal();
         i_orderEA = 0;
         i_win=0;
         i_loss=0;
         f_avgWin = 0;
         f_avgLoss = 0;
         // calculate average win, average loss and win%
         while (i_orderEA<i_windowLength && i_order>=0) {
            if (OrderSelect(i_order,SELECT_BY_POS,MODE_HISTORY)==true) {      // select order from history
               if (OrderMagicNumber() == myMagicNumber) {                     // make sure it was created by this EA
                  i_orderEA++;
                  if (OrderProfit()+OrderSwap()+OrderCommission()>0.001) {    // if a profitable trade
                     i_win++; 
                     f_avgWin = (((double)i_win-1)*f_avgWin + (OrderProfit()+OrderSwap()+OrderCommission())) / (double)i_win; }
                  else if (OrderProfit()+OrderSwap()+OrderCommission()< -0.001) {
                     i_loss++;
                     f_avgLoss = MathAbs((((double)i_loss-1)*f_avgLoss - (OrderProfit()+OrderSwap()+OrderCommission())) / (double)i_loss);
                  }
               }
            }
            else {
               Print("OrderSelect returned the error of ",GetLastError());
            }
            i_order--;
         }
         // compare with zero curve
         if (i_orderEA < i_windowLength) {                              // safety yet unknown -> trade conservatively
            lots = 0.1*sizeConst; }
         else {
            f_winPerc = (double)i_win/((double)i_win+(double)i_loss);
            if ((f_winPerc > 0) && (f_avgLoss > 0)) {
               f_zeroCurveDiff = (f_avgWin/f_avgLoss) - (1-f_winPerc)/f_winPerc;        // <0 is below the zero curve and vice versa
               if (f_zeroCurveDiff < 0) {         // below zero curve -> stop trading
                  lots = 0.01;
                  Print("TRADING BELOW THE ZERO CURVE"); }
               else if (f_zeroCurveDiff > f_safetyThreshold) {        // above the safety buffer - very profitable
                  lots = 1*sizeConst; }
               else {                        // trading in the safety zone - be cautious
                  lots = 0.5*sizeConst;}
               }
            else {                                                                           //no wins at all - stop trading
               lots = 0.01;
               Print("TRADING BELOW THE ZERO CURVE"); 
            }
         }
         // 2D distribution - we can optimise for stability of system by minimising variance - VARIANCE IS WRONG SEE VWAP!!!!!!!!!!!!!!!!
         if (f_avgLoss>0.001) {                          // make sure we dont divide by zero
            f_meanX = (f_safetyCounter/(f_safetyCounter+1))*f_meanX + (1.0/(f_safetyCounter+1))*f_winPerc;
            f_meanY = (f_safetyCounter/(f_safetyCounter+1))*f_meanY + (1.0/(f_safetyCounter+1))*f_avgWin/f_avgLoss;
            f_sigmaX = (f_safetyCounter/(f_safetyCounter+1))*f_sigmaX + MathPow((1.0/(f_safetyCounter+1))*(f_winPerc-f_meanX),2.0);
            f_sigmaY = (f_safetyCounter/(f_safetyCounter+1))*f_sigmaY + MathPow((1.0/(f_safetyCounter+1))*((f_avgWin/f_avgLoss)-f_meanY),2.0);
         }
         f_safetyCounter = f_safetyCounter + 1.0;
         // write to file
         if (IsTesting() && b_writeToFile) {
            h=FileOpen("safety.csv",FILE_WRITE|FILE_CSV|FILE_READ);
            if (h!=INVALID_HANDLE) {
               FileSeek(h,0,SEEK_END);
               FileWrite(h,i_trade,f_winPerc,f_avgWin,f_avgLoss,f_zeroCurveDiff); 
               FileClose(h); }
            else {
               Print("fileopen failed, error:",GetLastError()); 
            }
         }
         // update balance
         f_accountBalancePrev = AccountBalance();
         
     }
     
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
  
  int ticketPositionPending(int myMagicNumber, string symbol)
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol && (OrderType()==OP_BUYLIMIT || OrderType()==OP_SELLLIMIT || OrderType()==OP_SELLSTOP || OrderType()==OP_BUYSTOP))
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
  /**
  // magic number list
   if (StringCompare(StringSubstr(symbol,0,6),"EURUSD",false) == 0) { return stratMagicNumber*1000000 + 010000 + timeFrame; }          // G8 pairs
   else if (StringCompare(StringSubstr(symbol,0,6),"USDJPY",false) == 0) { return stratMagicNumber*1000000 + 020000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"GBPUSD",false) == 0) { return stratMagicNumber*1000000 + 030000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"AUDUSD",false) == 0) { return stratMagicNumber*1000000 + 040000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"NZDUSD",false) == 0) { return stratMagicNumber*1000000 + 050000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"EURJPY",false) == 0) { return stratMagicNumber*1000000 + 060000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"AUDJPY",false) == 0) { return stratMagicNumber*1000000 + 070000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"EURAUD",false) == 0) { return stratMagicNumber*1000000 + 080000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"USDCAD",false) == 0) { return stratMagicNumber*1000000 + 090000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"EURGBP",false) == 0) { return stratMagicNumber*1000000 + 100000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"USDCHF",false) == 0) { return stratMagicNumber*1000000 + 110000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"EURCHF",false) == 0) { return stratMagicNumber*1000000 + 120000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"GBPAUD",false) == 0) { return stratMagicNumber*1000000 + 130000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"EURCAD",false) == 0) { return stratMagicNumber*1000000 + 140000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"EURNZD",false) == 0) { return stratMagicNumber*1000000 + 150000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"GBPCHF",false) == 0) { return stratMagicNumber*1000000 + 160000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"GBPJPY",false) == 0) { return stratMagicNumber*1000000 + 170000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"GBPCAD",false) == 0) { return stratMagicNumber*1000000 + 180000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"GBPNZD",false) == 0) { return stratMagicNumber*1000000 + 190000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"CHFJPY",false) == 0) { return stratMagicNumber*1000000 + 200000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"AUDCHF",false) == 0) { return stratMagicNumber*1000000 + 210000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"CADCHF",false) == 0) { return stratMagicNumber*1000000 + 220000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"NZDCHF",false) == 0) { return stratMagicNumber*1000000 + 230000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"CADJPY",false) == 0) { return stratMagicNumber*1000000 + 240000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"NZDJPY",false) == 0) { return stratMagicNumber*1000000 + 250000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"AUDCAD",false) == 0) { return stratMagicNumber*1000000 + 260000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"AUDNZD",false) == 0) { return stratMagicNumber*1000000 + 270000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"NZDCAD",false) == 0) { return stratMagicNumber*1000000 + 280000 + timeFrame; }
   
   else if (StringCompare(StringSubstr(symbol,0,6),"USDSGD",false) == 0) { return stratMagicNumber*1000000 + 290000 + timeFrame; }       //SGD and other EM pairs
   else if (StringCompare(StringSubstr(symbol,0,6),"USDTRY",false) == 0) { return stratMagicNumber*1000000 + 300000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"USDNOK",false) == 0) { return stratMagicNumber*1000000 + 310000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"EURSGD",false) == 0) { return stratMagicNumber*1000000 + 320000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"GBPSGD",false) == 0) { return stratMagicNumber*1000000 + 330000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"SGDJPY",false) == 0) { return stratMagicNumber*1000000 + 340000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"NZDSGD",false) == 0) { return stratMagicNumber*1000000 + 350000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"CADSGD",false) == 0) { return stratMagicNumber*1000000 + 360000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"CHFSGD",false) == 0) { return stratMagicNumber*1000000 + 370000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"AUDSGD",false) == 0) { return stratMagicNumber*1000000 + 380000 + timeFrame; }
   
   else if (StringCompare(StringSubstr(symbol,0,6),"XAUUSD",false) == 0) { return stratMagicNumber*1000000 + 710000 + timeFrame; }       // gold and silver
   else if (StringCompare(StringSubstr(symbol,0,6),"XAUEUR",false) == 0) { return stratMagicNumber*1000000 + 720000 + timeFrame; }
   else if (StringCompare(StringSubstr(symbol,0,6),"XAGUSD",false) == 0) { return stratMagicNumber*1000000 + 730000 + timeFrame; }
   
   else if (StringCompare(symbol,"SPX500",false) == 0) { return stratMagicNumber*1000000 + 810000 + timeFrame; }
   else if (StringCompare(symbol,"US30",false) == 0) { return stratMagicNumber*1000000 + 820000 + timeFrame; }
   else if (StringCompare(symbol,"UK100",false) == 0) { return stratMagicNumber*1000000 + 830000 + timeFrame; }
   else if (StringCompare(symbol,"FRA40",false) == 0) { return stratMagicNumber*1000000 + 840000 + timeFrame; }
   else if (StringCompare(symbol,"ESTX50",false) == 0) { return stratMagicNumber*1000000 + 850000 + timeFrame; }
   else if (StringCompare(symbol,"WTI",false) == 0) { return stratMagicNumber*1000000 + 860000 + timeFrame; }
   else if (StringCompare(symbol,"BRENT",false) == 0) { return stratMagicNumber*1000000 + 870000 + timeFrame; }
   else { 
      return stratMagicNumber*1000000 + 990000 + timeFrame; 
      Alert("THIS IS UNDECLARED CROSS - The backup magic number is assigned.");
   }
  }
  **/
  bool readLastTradeSubComment(int myMagicNumber,string symbol,bool b_searchHistory, double &output[])
  {
   string result[];
   ushort u_sep=StringGetCharacter("_",0);
   int temp;
   ArrayInitialize(output,0);
   if (b_searchHistory) {
      for(int i=OrdersHistoryTotal()-1; i>=0; i--) {
         if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && OrderMagicNumber()==myMagicNumber && OrderSymbol()==symbol) {
            temp = StringSplit(OrderComment(),u_sep,result);
            if (ArraySize(result)<4) { PrintFormat("Comment format is wrong for ",symbol); break; }
            output[0] = StrToDouble(result[1]); //vwap
            output[1] = StrToDouble(result[2])+ OrderProfit() + OrderCommission() + OrderSwap();   // cum loss
            output[3] = (double)iBarShift(symbol,timeFrame,OrderCloseTime(),false);
            temp = StringFind(result[3],"[");
            if (temp<0) {
               output[2] = StrToDouble(result[3]); } // trade number
            else if (temp==1) {
               output[2] = StrToDouble(StringSubstr(result[3],0,1)); }
            else if (temp==2) {
               output[2] = StrToDouble(StringSubstr(result[3],0,2)); }
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
            if (ArraySize(result)<4) { PrintFormat("Comment format is wrong for %s",symbol); break; }
            output[0] = StrToDouble(result[1]); //vwap
            output[1] = StrToDouble(result[2]);   // cum loss
            output[2] = StrToDouble(result[3]); // trade number
            output[3] = 0.0;
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
  
  int findVWAPZone(double VWAPDiff,double sigma)                        // Function to find VWAP zone
  {
      /**             
   if (VWAPDiff<=-3*sigma) {
      return(-4); }
   else if ((VWAPDiff<=-2*sigma) && (VWAPDiff>-3*sigma)) {
      return(-3); }
   else if ((VWAPDiff<=-1*sigma) && (VWAPDiff>-2*sigma)) {
      return(-2); }
   else if ((VWAPDiff<=0*sigma) && (VWAPDiff>-1*sigma)) {
      return(-1); }
   else if ((VWAPDiff<=1*sigma) && (VWAPDiff>0*sigma)) {
      return(1); }
   else if ((VWAPDiff<=2*sigma) && (VWAPDiff>1*sigma)) {
      return(2); }
   else if ((VWAPDiff<=3*sigma) && (VWAPDiff>2*sigma)) {
      return(3); }
   else if (VWAPDiff>3*sigma) {
      return(4); }
   else { return(666); }**/
   
   
   if (VWAPDiff<=-1.5*sigma) {
      return(-2); }
   else if ((VWAPDiff<=0*sigma) && (VWAPDiff>-1.5*sigma)) {
      return(-1); }
   else if ((VWAPDiff<=1.5*sigma) && (VWAPDiff>0*sigma)) {
      return(1); }
   else if (VWAPDiff>1.5*sigma) {
      return(2); }
   else { return(666); }

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
