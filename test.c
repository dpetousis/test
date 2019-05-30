//﻿+------------------------------------------------------------------+
//|                        Copyright 2018, Dimitris Petousis         |
//+------------------------------------------------------------------+
#property strict

// DEFINITIONS & ENUMS ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
enum BOLLINGERMODE {
	NONE = 0, //NONE
	UPPER = 1, //MODE_UPPER
	LOWER = 2, //MODE_LOWER
};

// INPUTS ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//input switches & program constants 
double const bollinger_deviations = 4; //should be in input file
input BOLLINGERMODE bollinger_mode = UPPER;
double const f_percWarp = 0.25;
input double const f_percTP = 0.35;
int const bollinger_delay = 5; //should be in input file
input double m_profitInAccCcy=1;
double m_filter[4] ={30,7,15,15};      // bollinger freq,fast filter freq <2,fast filter freq, fast filter freq>£200
// statistics parameters
bool const b_statistics = true;
double const f_barSizePortion = 0.05;  // Gap = variable * (average bar size)
input int const i_bandsHistory = 50;       // history for averaging (both bars and bands) - adjusts every new sequence
int const filter_history = 50;		// fast filter history
// trading parameters
double const f_percSL = 1;
double const f_percAvBandSeparation = 1;  // pips to SL (or TP) = variable * ([average upper band] - [average lower band])
double const f_minBollingerBandRatio = 0;    // [min upper band] = [central band] + parameter * 0.5*([average upper band] - [average lower band]), ie 1 means the minimum is the average, 0 means the minimum is MAIN
double const f_adjustLevel = 1; //0.1; with 1, it basically never adjusts
int const slippage =10;           // in points
// Adjustments over loss level
double const f_FFAdjustLevel = 50;	// absolute level of loss after which we adjust
double const f_percTPAdjustLevel = 50;	// absolute level of loss after which we adjust TP
double const f_percTPAdjust = 0.26;		// kicks in after the loss level above is reached
double const f_bandsHistoryAdjustLevel = 50;   
int const i_bandsHistoryAdjust = 5;  
double const f_bandsHistoryAdjustMultiplier = 2.0; // bollinger deviation multiplier
double const f_adjustSFLevel = 50;		// resets SF to -1
int const f_adjustSFFreq = 4;			// reset SF every # trades in sequence

// TRADE ACCOUNTING VARIABLES ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
int const timeFrame=Period();    
int i_ordersTotal = 0,i_openSequenceForProduct=-1;
bool b_pendingGlobal=false,b_statsUpdated=false,b_slowFilterAdjusted=false;
int m_myMagicNumber;  // Magic Numbers
double m_accountCcyFactors;
double m_sequence[7] = {-1.0,0.0,0.0,0,0,0,0.0};   // 0:SF,1:Losses excl current,2:#,3:warp,4:SL,5:TP,6:FF freq
string const m_names = Symbol();
double m_bollingerDeviationInPips=0.0;   // [average upper band] - [average lower band]
double m_nonTradingWindows[4] = {0,0,0,0};		// CANNOT START NEW SEQUENCE IN WINDOW, 0: window1 start 1:window1 end 2: window2 start 3: window2 end, DEFAULT(new sequence always allowed): 0,0,0,0
int m_lotDigits;
double m_lotMin;
double m_lotMax;
int m_ticket=0;
double m_cumLosses=0.0;
double m_bandsTSAvg;
double m_barTSAvg;
double m_slowFilterGap=0.0;     // Gap = upper SF - SF = SF - lower SF
//bool m_newSequenceNotAllowed;
datetime m_lastTicketOpenTime=D'01.01.1999';

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   //double f_overlap,f_low1,f_low2,f_high1,f_high2,f_scale,f_barSizeTSAvg = 0.0;
   string s_symbolAppendix;
   
   m_sequence[3] = f_percWarp;
   m_sequence[4] = f_percSL;
   m_sequence[5] = f_percTP;
   m_sequence[6] = m_filter[1];
   
      // lot details
      m_lotDigits = (int)MathMax(-MathLog10(MarketInfo(m_names,MODE_LOTSTEP)),0);
      if (m_lotDigits<0) { Alert("Lot digits calculation is wrong for ",m_names); }
      m_lotMin = MarketInfo(m_names,MODE_MINLOT);
      m_lotMax = MarketInfo(m_names,MODE_MAXLOT);
      
      // STATISTICS
      statistics(m_bandsTSAvg,m_barTSAvg,i_bandsHistory);
   
   // initialize m_accountCcyFactors
   if (AccountCompany()=="ThinkMarkets.com") { if (IsDemo()) { s_symbolAppendix = "pro"; } else { s_symbolAppendix = "x"; } }      // "TF Global Markets (Aust) Pty Ltd"
   else if (AccountCompany()=="UOB") { s_symbolAppendix = "#"; }
   else if (AccountCompany()=="Admiral Markets") { s_symbolAppendix = ""; }
   else { s_symbolAppendix = ""; }
   m_accountCcyFactors = accCcyFactor(m_names,s_symbolAppendix);
   Alert("acc factor for: ",m_names," is ",m_accountCcyFactors);
   
   Alert ("Function init() triggered at start for ",Symbol());// Alert

   return(INIT_SUCCEEDED);
   }
  
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   Alert ("Function deinit() triggered at exit for ",Symbol());// Alert
   
   return;
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {

// VARIABLE DECLARATIONS /////////////////////////////////////////////////////////////////////////////////////////////////////////
   int ticket=0,price,i_ticketSum=0;
   uint tick=0;
   bool b_transition=false,b_tradeClosedBySL=false,res,b_pending=false,b_multiPositionOpen=false,b_aroundNewBar=false,b_checkEveryXMinute=false;
   double SL,TP,BID,ASK,f_fastFilterPrev=0.0,f_fastFilter=0.0,f_lotUnsplit=0,f_bollingerBandPrev = 0.0,f_bollingerBand = 0.0,temp_oldFF=0.0,temp_newFF=0.0,temp_pnlSum=0.0,f_timeInHours=0;
   string s_adjFlag="";
   int m_signal=0; // 0:lower, 1:upper crossing of slow filter
   bool m_isPositionOpen=false;
   bool m_isPositionPending=false;
   int m_positionDirection=0;
   bool m_close=false;
   int m_open=0;
   bool m_productOutOfHours=false;
   double m_loss=0;
   double m_slowFilter=0;
   double temp_sequence[8]={0,0,0,0,0,0,0,0};
   double m_lots=0;
   double temp_pnl = 0;
   double temp_T[2] = {0,0};

// UPDATE STATISTICS ////////////////////////////////////////////////////////////////////////////////////////////////
if (Hour()==1 && b_statsUpdated==false) {
   m_bandsTSAvg=0.0;
   m_barTSAvg=0.0;
   statistics(m_bandsTSAvg,m_barTSAvg,i_bandsHistory);
   b_statsUpdated=true;
} else if (Hour()==2 && b_statsUpdated==true) { b_statsUpdated=false; }
   
// UPDATE STATUS/////////////////////////////////////////////////////////////////////////////////////////////////////
// Make sure rest of ontimer() does not run continuously when not needed
if (m_ticket>0) {
	   res = OrderSelect(m_ticket,SELECT_BY_TICKET);
		if (res) {
			if (OrderCloseTime()>0) {			// if closed
				//b_tradeClosedBySL = (temp_sequence[6]>0.5) ? true : false;
				temp_pnl = OrderProfit() + OrderCommission() + OrderSwap();
				m_isPositionOpen=false;
				m_isPositionPending = false;
				m_positionDirection = 0;
			}
			else {
				if (OrderType()==OP_BUY) { 
					m_isPositionOpen=true;
					m_isPositionPending = false;
					m_positionDirection = 1; }
				else if (OrderType()==OP_SELL) { 
					m_isPositionOpen=true;
					m_isPositionPending = false;
					m_positionDirection = -1; }
				else if (OrderType()==OP_SELLSTOP || OrderType()==OP_SELLLIMIT) { 								// pending
					m_isPositionOpen=false;
					m_isPositionPending = true; 
					m_positionDirection = -1; }
				else if (OrderType()==OP_BUYSTOP || OrderType()==OP_BUYLIMIT) { 								// pending
					m_isPositionOpen=false;
					m_isPositionPending = true; 
					m_positionDirection = 1; 
				}
			}
		}
		else { Alert("Failed to select trade: ",m_ticket); }
		b_multiPositionOpen = b_multiPositionOpen || (m_isPositionOpen || m_isPositionPending);
		i_ticketSum = i_ticketSum + m_ticket;
		b_pending = b_pending || m_isPositionPending; // this is checking across all trades and names
   }
if (!b_multiPositionOpen && i_ticketSum>0.5) {    // order is closed if no open positions but ticket numbers not yet reset
   temp_pnlSum = temp_pnlSum + temp_pnl;
   if ((m_sequence[1]+temp_pnlSum)>=0.01) {	//ie trade sequence closed positive/negative by one cent or penny
		m_sequence[0] = -1;
		for(int k=1; k<3; k++) { m_sequence[k] = 0; }
		m_sequence[3] = f_percWarp;
		m_sequence[4] = f_percSL;
		m_sequence[5] = f_percTP;
		m_sequence[6] = m_filter[1];    // FF freq
		m_slowFilterGap = 0.0;
		m_bollingerDeviationInPips = 0;
		b_slowFilterAdjusted = false;
	}
	else {
	   // dont copy over slow filter because it may have been modified externally
	   m_sequence[1] = m_sequence[1] + temp_pnlSum;
	}
	m_ticket = 0; 
	m_cumLosses = m_cumLosses + temp_pnl;

}
temp_pnl = 0.0; 
temp_pnlSum = 0.0;
b_multiPositionOpen = false;
b_pendingGlobal = b_pending;
  
// INDICATOR BUFFERS ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
		if ((m_sequence[0]<0) || (m_sequence[2]<1.5 && iBarShift(m_names,timeFrame,m_lastTicketOpenTime,false)==0)) {	// no sequence or new sequence opened this bar                      // SF
			// This is to deal with the special case of opening new sequence. In the first bar, we should always be in the "if" part of the loop.
			f_fastFilter = iCustom(m_names,0,"petousis_decycler",m_filter[1],filter_history,1,1);   // FF fast value
			f_fastFilterPrev = iCustom(m_names,0,"petousis_decycler",m_filter[1],filter_history,1,2);
         //f_fastFilter = iMA(m_names,0,(int)m_filter[1],0,3,PRICE_CLOSE,1);   // FF fast value
         //f_fastFilterPrev = iMA(m_names,0,(int)m_filter[1],0,3,PRICE_CLOSE,2);
			if (bollinger_mode==UPPER) {
				f_bollingerBand = MathMax(iBands(m_names,timeFrame,(int)m_filter[0],bollinger_deviations,0,0,bollinger_mode,1+bollinger_delay),
									iBands(m_names,timeFrame,(int)m_filter[0],bollinger_deviations,0,0,MODE_MAIN,1+bollinger_delay) + f_minBollingerBandRatio*0.5*m_bandsTSAvg*MarketInfo(m_names,MODE_POINT));
				f_bollingerBandPrev = MathMax(iBands(m_names,timeFrame,(int)m_filter[0],bollinger_deviations,0,0,bollinger_mode,2+bollinger_delay),
									iBands(m_names,timeFrame,(int)m_filter[0],bollinger_deviations,0,0,MODE_MAIN,2+bollinger_delay) + f_minBollingerBandRatio*0.5*m_bandsTSAvg*MarketInfo(m_names,MODE_POINT)); 
			}
			else if (bollinger_mode==LOWER) {
				f_bollingerBand = MathMin(iBands(m_names,timeFrame,(int)m_filter[0],bollinger_deviations,0,0,bollinger_mode,1+bollinger_delay),
									iBands(m_names,timeFrame,(int)m_filter[0],bollinger_deviations,0,0,MODE_MAIN,1+bollinger_delay) - f_minBollingerBandRatio*0.5*m_bandsTSAvg*MarketInfo(m_names,MODE_POINT));
				f_bollingerBandPrev = MathMin(iBands(m_names,timeFrame,(int)m_filter[0],bollinger_deviations,0,0,bollinger_mode,2+bollinger_delay),
									iBands(m_names,timeFrame,(int)m_filter[0],bollinger_deviations,0,0,MODE_MAIN,2+bollinger_delay) - f_minBollingerBandRatio*0.5*m_bandsTSAvg*MarketInfo(m_names,MODE_POINT)); 
			}
			else { Alert("Bollinger mode is neither lower nor upper - cannot calculate slow filter."); }
			temp_T[0] = (f_fastFilter - f_bollingerBand)*(f_fastFilterPrev - f_bollingerBandPrev);
			temp_T[1] = temp_T[0];
			//Alert(f_fastFilter,",",f_bollingerBand,",",f_fastFilterPrev,",",f_bollingerBandPrev);
		}
		else {		// existing sequence
			f_bollingerBand = m_sequence[0];
			f_bollingerBandPrev = f_bollingerBand;
			int fFilterCurrent = (int)m_sequence[6];
			int fFilterCorrect;
			if (m_sequence[2]<1.5) { fFilterCorrect = (int)m_filter[1]; }
			else if (m_sequence[2]>1.5 && m_sequence[1]<-f_FFAdjustLevel) { fFilterCorrect = (int)m_filter[3]; }  // Third filter value when long sequence
			else { fFilterCorrect = (int)m_filter[2]; }
         if (fFilterCurrent!=fFilterCorrect) {
				//temp_oldFF = iMA(m_names,0,fFilterCurrent,0,3,PRICE_CLOSE,1);
				//temp_newFF = iMA(m_names,0,fFilterCorrect,0,3,PRICE_CLOSE,1);
				temp_oldFF = iCustom(m_names,0,"petousis_decycler",fFilterCurrent,filter_history,1,1); 
				temp_newFF = iCustom(m_names,0,"petousis_decycler",fFilterCorrect,filter_history,1,1);
				b_transition = (temp_oldFF<f_bollingerBand-m_slowFilterGap && temp_newFF<f_bollingerBand-m_slowFilterGap) ||
				(temp_oldFF>f_bollingerBand+m_slowFilterGap && temp_newFF>f_bollingerBand+m_slowFilterGap) ||
				(temp_oldFF>f_bollingerBand-m_slowFilterGap && temp_oldFF<f_bollingerBand+m_slowFilterGap && temp_newFF>f_bollingerBand-m_slowFilterGap && temp_newFF<f_bollingerBand+m_slowFilterGap);
				if (b_transition) { //transition if current slow FF is in the same region as current fast FF
					f_fastFilter = temp_newFF;   
					f_fastFilterPrev = iCustom(m_names,0,"petousis_decycler",fFilterCorrect,filter_history,1,2);
					//f_fastFilterPrev = iMA(m_names,0,fFilterCorrect,0,3,PRICE_CLOSE,2);
					m_sequence[6] = fFilterCorrect;
				}
				else { // dont transition
					f_fastFilter = temp_oldFF;   
					f_fastFilterPrev = iCustom(m_names,0,"petousis_decycler",fFilterCurrent,filter_history,1,2);
					//f_fastFilterPrev = iMA(m_names,0,fFilterCurrent,0,3,PRICE_CLOSE,2);
				}
			}
			else {
				f_fastFilter = iCustom(m_names,0,"petousis_decycler",fFilterCurrent,filter_history,1,1);   
				f_fastFilterPrev = iCustom(m_names,0,"petousis_decycler",fFilterCurrent,filter_history,1,2);
				//f_fastFilter = iMA(m_names,0,fFilterCurrent,0,3,PRICE_CLOSE,1);
				//f_fastFilterPrev = iMA(m_names,0,fFilterCurrent,0,3,PRICE_CLOSE,2);
			}
			temp_T[0] = (f_fastFilter - (f_bollingerBand-m_slowFilterGap))*(f_fastFilterPrev - (f_bollingerBandPrev-m_slowFilterGap));
			temp_T[1] = (f_fastFilter - (f_bollingerBand+m_slowFilterGap))*(f_fastFilterPrev - (f_bollingerBandPrev+m_slowFilterGap));
		}
	         
          if (temp_T[0] < 0 || temp_T[1] < 0) {
            if (m_sequence[0]<0) {         // either new sequence or manually set (-1) mid-sequence, so update the pips
               m_bandsTSAvg=0.0;
               m_barTSAvg=0.0;
               statistics(m_bandsTSAvg,m_barTSAvg,i_bandsHistory);
	            m_bollingerDeviationInPips = NormalizeDouble(f_percAvBandSeparation*m_bandsTSAvg,0);
	            m_slowFilterGap = NormalizeDouble(m_barTSAvg * f_barSizePortion, (int)MarketInfo(m_names,MODE_DIGITS));  // quarter the bar size: lower SF=SF-m_slowFilterGap, upper SF=SF+m_slowFilterGap
	            if (f_fastFilter>f_bollingerBand) { 
                  // when on free moving slow filter only enter buy on upper and sell on lower.
                  if (bollinger_mode==1) { m_signal = 2; } else { m_signal = 0; } 
                  //Alert(f_fastFilter,",",f_bollingerBand,",",f_fastFilterPrev,",",f_bollingerBandPrev,"signal=",m_signal);
                  // Use fast filter to set slow filter level if 1) new sequence or 2) change larger than f_adjustLevel
                  m_sequence[0] = MathMax(f_bollingerBand,f_fastFilter-f_adjustLevel*m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT));
               }
               else if (f_fastFilter<f_bollingerBand) { 
                  // when on free moving slow filter only enter buy on upper and sell on lower.
                  if (bollinger_mode==2) { m_signal = -2; } else { m_signal = 0; }
                  //Alert(f_fastFilter,",",f_bollingerBand,",",f_fastFilterPrev,",",f_bollingerBandPrev,"signal=",m_signal);
                  // Use fast filter to set slow filter level if 1) new sequence or 2) change larger than f_adjustLevel
                  m_sequence[0] = MathMin(f_bollingerBand,f_fastFilter+f_adjustLevel*m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT));
               }
               // confirm new sequence can be opened for product
			      f_timeInHours = (double)Hour() + (double)Minute()/60;
			      m_productOutOfHours = ((f_timeInHours>=m_nonTradingWindows[0])&&(f_timeInHours<m_nonTradingWindows[1])) || ((f_timeInHours>=m_nonTradingWindows[2])&&(f_timeInHours<m_nonTradingWindows[3]));
			      //Alert("signal=",m_signal);
            }
            else {
               if (m_sequence[1]<-f_bandsHistoryAdjustLevel) {			// adjust if needed
                     m_bandsTSAvg=0.0;
                     m_barTSAvg=0.0;
                     statistics(m_bandsTSAvg,m_barTSAvg,i_bandsHistoryAdjust);
                     m_bollingerDeviationInPips = NormalizeDouble(f_bandsHistoryAdjustMultiplier*f_percAvBandSeparation*m_bandsTSAvg,0);
               }
			   if (m_sequence[1]<-f_percTPAdjustLevel) {
					m_sequence[5]	= f_percTPAdjust;
			   }
               if (f_fastFilter>f_bollingerBand+m_slowFilterGap) { 
                  m_signal = 2;
                  // Use fast filter to set slow filter level if 1) new sequence or 2) change larger than f_adjustLevel
                  if (MathAbs(m_sequence[0]-f_fastFilter)>f_adjustLevel*m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT)) { 
            			m_sequence[0] = f_fastFilter - MarketInfo(m_names,MODE_POINT); 
            		}
					else if (m_sequence[1]<-f_adjustSFLevel && !b_slowFilterAdjusted) {
						m_sequence[0] = -1.0;
						//else { m_sequence[0] = MathMin(m_sequence[0],f_fastFilter - 0.5 * m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT)); }
						b_slowFilterAdjusted = true;
					}
   		         //else { m_slowFilter = m_sequence[0]; }
               }
               else if (f_fastFilter>f_bollingerBand-m_slowFilterGap && f_fastFilter<f_bollingerBand+m_slowFilterGap && f_fastFilterPrev<f_bollingerBand-m_slowFilterGap) {
                  m_signal = 1;
               }
               else if (f_fastFilter>f_bollingerBand-m_slowFilterGap && f_fastFilter<f_bollingerBand+m_slowFilterGap && f_fastFilterPrev>f_bollingerBand+m_slowFilterGap) {
                  m_signal = -1;
               }
   	         else if (f_fastFilter<f_bollingerBand-m_slowFilterGap) { 
                  m_signal = -2;
                  // Use fast filter to set slow filter level if 1) new sequence or 2) change larger than f_adjustLevel
                  if (MathAbs(m_sequence[0]-f_fastFilter)>f_adjustLevel*m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT)) { 
            			m_sequence[0] = f_fastFilter + MarketInfo(m_names,MODE_POINT); 
            		}
					else if (m_sequence[1]<-f_adjustSFLevel && !b_slowFilterAdjusted) {
						m_sequence[0] = -1.0;
						//else { m_sequence[0] = MathMax(m_sequence[0],f_fastFilter + 0.5*m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT)); }
						b_slowFilterAdjusted = true;
					}
   		         //else { m_slowFilter = m_sequence[0]; }
               }
               else { m_signal = 0; }
               //Alert("signal(else)=",m_signal);
            }
		   }
        else { m_signal = 0; }
      
// INTERPRET SIGNAL /////////////////////////////////////////////////////////////////////////////////////////////////////////
   if ( m_signal!=0) {
         if (m_signal>0 && m_positionDirection<0 && iBarShift(m_names,timeFrame,m_lastTicketOpenTime,false)!=0) { m_close=true; }
         else if (m_signal>1 && m_positionDirection==0 && iBarShift(m_names,timeFrame,m_lastTicketOpenTime,false)!=0) { m_open=1;  }
         else if (m_signal<0 && m_positionDirection>0 && iBarShift(m_names,timeFrame,m_lastTicketOpenTime,false)!=0) { m_close=true; }
         else if (m_signal<-1 && m_positionDirection==0 && iBarShift(m_names,timeFrame,m_lastTicketOpenTime,false)!=0) { m_open=-1;  }
         else { }// do nothing
         //Alert("m_open=",m_open,"m_positionDirection=",m_positionDirection,"m_lastTicketOpenTime=",m_lastTicketOpenTime);
}
   
// CLOSING ORDERS //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
         if (m_close) {
               RefreshRates();
               Alert("Attempt to close ",m_ticket); 
      			res = OrderSelect(m_ticket,SELECT_BY_TICKET);
      			if(OrderType()==0) {price=MODE_BID;} else {price=MODE_ASK;}
      			if (m_isPositionPending==true) { res = OrderDelete(m_ticket); }
      			else { res = OrderClose(m_ticket,OrderLots(),MarketInfo(m_names,price),100); }         // slippage 100, so it always closes
               if (res==true) { Alert("Order closed."); }
               else { Alert("Order close failed."); }
         }
 
 // OPENING ORDERS //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      if (false) { //m_isPositionPending==true && m_open==0) {     // if pending order exists -> modify pending order
       		RefreshRates(); 
      		if (m_positionDirection==1) { 
      			ASK = MarketInfo(m_names,MODE_ASK)-MarketInfo(m_names,MODE_STOPLEVEL)*MarketInfo(m_names,MODE_POINT);
				SL=NormalizeDouble(ASK - m_sequence[4] * m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT),(int)MarketInfo(m_names,MODE_DIGITS));
                 TP=NormalizeDouble(ASK + m_sequence[5] * m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT),(int)MarketInfo(m_names,MODE_DIGITS));   // Calculating TP of opened
      			res = OrderModify(m_ticket,ASK,SL,TP,0); 
      		}
      		else if (m_positionDirection==-1) { 
      			BID = MarketInfo(m_names,MODE_BID)+MarketInfo(m_names,MODE_STOPLEVEL)*MarketInfo(m_names,MODE_POINT);
         		SL=NormalizeDouble(BID + m_sequence[4]*m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT),(int)MarketInfo(m_names,MODE_DIGITS));
				TP=NormalizeDouble(BID - m_sequence[5]*m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT),(int)MarketInfo(m_names,MODE_DIGITS));   // Calculating TP of opened
      			res = OrderModify(m_ticket,BID,SL,TP,0); 
      		}
      		else { res=false; }
       		if (res) { Print("Order modified successfully:",m_names); }
       		else { Alert(m_names,": Order modification failed with error #", GetLastError()); }
    	}
      // Send order when no new sequence flag is off and product is not out of hours
      if (true) {   
            
			if (m_open>0 || m_open<0) {
				// Loss per name
					m_loss = -m_sequence[1]; 
				// Lots per trade
				m_lots = MathMax(m_profitInAccCcy,MathAbs(m_loss)/m_sequence[3]) / m_accountCcyFactors / m_bollingerDeviationInPips;
				m_lots = NormalizeDouble(MathMin(m_lotMax,MathMax(m_lotMin,m_lots)),m_lotDigits);  // floor and normalize
			}
			RefreshRates();                        // Refresh rates
			
            // OPEN BUY
            if (m_open>0) {                                       // criterion for opening Buy
               
               // LEVELS
               //ASK = MarketInfo(m_names,MODE_ASK)-MarketInfo(m_names,MODE_STOPLEVEL)*MarketInfo(m_names,MODE_POINT);
			   SL=NormalizeDouble(Ask - m_sequence[4]*m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT),(int)MarketInfo(m_names,MODE_DIGITS));
               TP=NormalizeDouble(Ask + m_sequence[5]*m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT),(int)MarketInfo(m_names,MODE_DIGITS));   // Calculating TP of opened
               
               // ORDER
               ticket=OrderSend(m_names,OP_BUY,m_lots,Ask,slippage,SL,TP,"",m_myMagicNumber); //Opening Buy
           }
         // OPEN SELL
         if (m_open<0) {                                       // criterion for opening Sell
            
            // LEVELS
            //BID = MarketInfo(m_names,MODE_BID)+MarketInfo(m_names,MODE_STOPLEVEL)*MarketInfo(m_names,MODE_POINT);
			SL=NormalizeDouble(Bid + m_sequence[4]*m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT),(int)MarketInfo(m_names,MODE_DIGITS));
            TP=NormalizeDouble(Bid - m_sequence[5]*m_bollingerDeviationInPips*MarketInfo(m_names,MODE_POINT),(int)MarketInfo(m_names,MODE_DIGITS));   // Calculating TP of opened
            
			// ORDER 
            ticket=OrderSend(m_names,OP_SELL,m_lots,Bid,slippage,SL,TP,"",m_myMagicNumber); //Opening Sell
         }
         // ALERTS AND ACCOUNTiNG
         if (m_open<0 || m_open>0) {
            Print("OrderSend returned:",ticket," Lots: ",m_lots); 
            if (ticket < 0)     {                 
               Alert("OrderSend failed with error #", GetLastError());
               Alert("Loss: ",-m_loss,". Factor: ",m_accountCcyFactors,". Pips: ",m_bollingerDeviationInPips,". SL: ",SL,". TP: ",TP);
            }
            else {				// Success :)
               //if (m_open<0) { m_sequence[0] = MathCeil(m_slowFilter/MarketInfo(m_names,MODE_POINT))*MarketInfo(m_names,MODE_POINT); }
               //else { m_sequence[0] = MathFloor(m_slowFilter/MarketInfo(m_names,MODE_POINT))*MarketInfo(m_names,MODE_POINT); }
               m_sequence[2] = m_sequence[2] + 1;                       // increment trade number if it is the main trade                            // main
			   if (MathMod(m_sequence[2],f_adjustSFFreq)<0.5) { b_slowFilterAdjusted = false; }	// adjust SF every "f_adjustSFFreq" trades
               Alert ("Opened pending order ",ticket,",Symbol:",m_names," Lots:",m_lots);
   			   m_ticket = ticket;
   			   m_lastTicketOpenTime = TimeCurrent(); 
      			m_sequence[1] = -m_loss; 
			  }
         }
                                       
        }

   return;                                      // exit start()
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
  
  void statistics(double &m_bandsTSAvgLocal, double &m_barTSAvgLocal, int const history)
  {
     double f_barSizeTSAvg=0.0, f_overlap=0.0, f_low1, f_low2, f_high1, f_high2, f_scale;
     for (int j=0;j<history;j++) {
   	   // measure of bar size vs band width
   	   m_bandsTSAvgLocal = m_bandsTSAvgLocal + iBands(m_names,timeFrame,(int)m_filter[0],bollinger_deviations,0,0,MODE_UPPER,j+1) - 
   						iBands(m_names,timeFrame,(int)m_filter[0],bollinger_deviations,0,0,MODE_LOWER,j+1);
   	   f_barSizeTSAvg = f_barSizeTSAvg + iHigh(m_names,timeFrame,j+1) - iLow(m_names,timeFrame,j+1);
   	   // neighbouring-bar overlap measure
   	   f_low1 = MathMin(iClose(m_names,timeFrame,j+1),iOpen(m_names,timeFrame,j+1));
   	   f_low2 = MathMin(iClose(m_names,timeFrame,j+2),iOpen(m_names,timeFrame,j+2));
   	   f_high1 = MathMax(iClose(m_names,timeFrame,j+1),iOpen(m_names,timeFrame,j+1));
   	   f_high2 = MathMax(iClose(m_names,timeFrame,j+2),iOpen(m_names,timeFrame,j+2));
   	   f_scale = MathMax(iHigh(m_names,timeFrame,j+1),iHigh(m_names,timeFrame,j+2)) - MathMin(iLow(m_names,timeFrame,j+1),iLow(m_names,timeFrame,j+2));
   	   if (MathAbs(f_scale)>0.000001) { f_overlap = f_overlap + MathMax((MathMin(f_high1,f_high2)-MathMax(f_low1,f_low2))/f_scale,0.0); }
     }
     m_bandsTSAvgLocal = NormalizeDouble((1/MarketInfo(m_names,MODE_POINT)) * m_bandsTSAvgLocal / history, 0); // in pips
     Alert(m_names," Average band in pips: ",m_bandsTSAvgLocal);
     m_barTSAvgLocal = NormalizeDouble(f_barSizeTSAvg / history, (int)MarketInfo(m_names,MODE_DIGITS));
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
  
  double cumulativePnL()
  {
      double pnl = 0;
      pnl = m_cumLosses;
      return pnl;
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