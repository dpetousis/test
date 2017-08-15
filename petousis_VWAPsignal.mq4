//+------------------------------------------------------------------+
//|                                                   cAlligator.mq4 |
//|                        Copyright 2015, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2015, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#property indicator_chart_window
//#property indicator_separate_window
//#property indicator_minimum -1.0
//#property indicator_maximum 1.0
#property indicator_buffers 5
//#property indicator_plots   1
//--- plot Label1
//#property indicator_label1  "Label1"
//#property indicator_type1   DRAW_LINE
//#property indicator_color1  clrRed
//#property indicator_style1  STYLE_SOLID
//#property indicator_width1  1
//--- indicator buffers
double         buf_price[];
double         buf_VWAP[];
double         buf_filter[];
double         buf_signal[];
double         buf_centralVWAP[];   // This is the VWAP line with 0 deviation
//--- Other parameters
input int i_period = 200;   // rolling window
input int filter_cutoff = 30;
input const int i_mode = 1; // 2:MA 1:VWAP or 3:BOLLINGER
input bool b_supersmoother = true;
input bool b_sendEmail = false;
// this is the deviation from VWAP, 0 means it is the VWAP
input double f_deviationPerc= 0.0;
input int i_history = 10000;
input double f_fixVWAP = -1.0;
double f_mew=0,f_mew2=0,f_sigma=0;
int barLastSentEmail=0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- indicator buffers mapping
   
   SetIndexBuffer(0,buf_price);
   //SetIndexStyle(0,DRAW_LINE,STYLE_SOLID,2,clrTomato);
   
   SetIndexBuffer(1,buf_filter);
   SetIndexStyle(1,DRAW_LINE,STYLE_SOLID,2,clrSilver);
   
   SetIndexBuffer(2,buf_VWAP);
   SetIndexStyle(2,DRAW_LINE,STYLE_SOLID,2,clrTomato);
   
   SetIndexBuffer(3,buf_signal);
   SetIndexStyle(3,DRAW_ARROW,STYLE_SOLID,4,clrRed);
   
   SetIndexBuffer(4,buf_centralVWAP);
   //SetIndexStyle(2,DRAW_LINE,STYLE_SOLID,2,clrTomato);
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
//---
   int i;                              // Bar index
   int    i_limit;                              // Index of indicator array element
   int     i_countedBars;                   // Number of counted bars
   double f_cumPriceVolume=0,f_cumVolume=0.0,f_n=0.0,f_alpha=0.0,f_beta=0.0,f_c1=0,f_c2=0,f_c3=0; 
   bool temp;     
//--------------------------------------------------------------------

   i_countedBars=IndicatorCounted();    // Number of counted bars
   i_limit=Bars-i_countedBars-1;              // Index of the 1st uncounted
   if (i_limit>i_history-1) {                   // If too many bars ..
      i_limit=i_history-1;                     // ..calculate for specified amount.
   }
   
   for (i=i_limit; i>=0;i--) {                     // >= calculates also current bar, > does not
      
      buf_price[i] = (high[i]+low[i]+close[i])/3;
      
      if ((i>=i_limit-i_period) && (i_limit>1)) {        // Initialize only at beggining, not at every live tick
         buf_VWAP[i] = buf_price[i];
         buf_centralVWAP[i] = buf_price[i];
         buf_filter[i] = 0;
      }
      else {
         // calc vwap
         if (f_fixVWAP < 0.0) {
            switch(i_mode) 
            {
               case 1:
                  for (int j=i_period-1; j>=0; j--) {
                     f_cumPriceVolume = f_cumPriceVolume + buf_price[i+j]*tick_volume[i+j];
                     f_cumVolume = f_cumVolume + tick_volume[i+j];
                  }
                  buf_VWAP[i] = (1 + f_deviationPerc/100) * (f_cumPriceVolume / f_cumVolume);
                  buf_centralVWAP[i] = f_cumPriceVolume / f_cumVolume;
                  f_cumPriceVolume=0;
                  f_cumVolume=0.0;  
                  break;
               case 2:
                  buf_VWAP[i] = (1 + f_deviationPerc/100) * iMA(NULL,0,i_period,0,MODE_SMA,PRICE_CLOSE,i);
                  buf_centralVWAP[i] = iMA(NULL,0,i_period,0,MODE_SMA,PRICE_CLOSE,i);
                  break;
               case 3:
                  if (f_deviationPerc>0) {
                     buf_VWAP[i] = iBands(NULL,0,i_period,f_deviationPerc,0,PRICE_CLOSE,MODE_UPPER,i); }
                  else if (f_deviationPerc<0) {
                     buf_VWAP[i] = iBands(NULL,0,i_period,MathAbs(f_deviationPerc),0,PRICE_CLOSE,MODE_LOWER,i); }
                  else {
                     buf_VWAP[i] = iBands(NULL,0,i_period,f_deviationPerc,0,PRICE_CLOSE,MODE_MAIN,i);
                  }
                  buf_centralVWAP[i] = iBands(NULL,0,i_period,f_deviationPerc,0,PRICE_CLOSE,MODE_MAIN,i);
                  break;
             }
         }
         else {
            buf_VWAP[i] = f_fixVWAP;
            buf_centralVWAP[i] = f_fixVWAP;
         }
         
         // filter
         if (b_supersmoother) {
            // supersmoother
            f_alpha = MathExp(-1.414*M_PI/(double)filter_cutoff);
            f_beta = 2 * f_alpha * cos(1.414*M_PI/(double)filter_cutoff);
            f_c2 = f_beta;
            f_c3 = - f_alpha * f_alpha;
            f_c1 = 1 - f_c2 - f_c3;
            buf_filter[i] = (f_c1*(close[i]+close[i+1])/2) + f_c2*buf_filter[i+1] + f_c3*buf_filter[i+2]; 
         }
         else {
            // calc decycler with the close only
            f_alpha = (cos(2*M_PI/(double)filter_cutoff) + sin(2*M_PI/(double)filter_cutoff) - 1) / cos(2*M_PI/(double)filter_cutoff);
            buf_filter[i] = (f_alpha/2)*(close[i]+close[i+1]) + (1-f_alpha)*buf_filter[i+1]; 
         }
         
         // get signal
         if ((buf_VWAP[i] - buf_filter[i]) * (buf_VWAP[i+1] - buf_filter[i+1]) < 0) {
            if (buf_filter[i] > buf_VWAP[i]) {
               buf_signal[i] = 1.002*buf_VWAP[i]; 
               if (b_sendEmail && i==0 && Bars!=barLastSentEmail) { 
                  temp = SendMail("TRADE ALERT",Symbol()+" "+DoubleToStr(Period(),0)+" BUY"); 
                  if (temp==false) { Alert(Symbol()+" "+DoubleToStr(Period(),0)," Email could not be sent.");  }
                  barLastSentEmail = Bars;
               }
            }
            else {
               buf_signal[i] = 0.998*buf_VWAP[i];
               if (b_sendEmail && i==0 && Bars!=barLastSentEmail) { 
                  temp = SendMail("TRADE ALERT",Symbol()+" "+DoubleToStr(Period(),0)+" SELL"); 
                  if (temp==false) { Alert(Symbol()+" "+DoubleToStr(Period(),0)," Email could not be sent.");  }
                  barLastSentEmail = Bars;
               }
            }
         }
         else {
            buf_signal[i] = 0.0;
         }
      }
   }
 
//--- return value of prev_calculated for next call
   return(rates_total);
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

double   ArrayMedian(double &array[],int i_len, int i_start)
      {
      double median;
      double copy[];
      ArrayResize(copy,i_len);
      ArrayCopy(copy,array,0,i_start,i_len);
      ArraySort(copy,WHOLE_ARRAY,0,MODE_DESCEND);
      // ONLY WORKS WITH i_len ODD
      median=copy[(i_len-1)/2];
      return(median);
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