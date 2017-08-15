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
//#property indicator_minimum -1.5
//#property indicator_maximum 1.5
#property indicator_buffers 2
//#property indicator_plots   1
//--- plot Label1
//#property indicator_label1  "Label1"
//#property indicator_type1   DRAW_LINE
//#property indicator_color1  clrRed
//#property indicator_style1  STYLE_SOLID
//#property indicator_width1  1
//--- indicator buffers
double         buf_price[];
double         buf_filter[];
//--- Other parameters
input int i_period = 10;
input int i_history = 5000;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- indicator buffers mapping
   
   SetIndexBuffer(0,buf_price);
   
   SetIndexBuffer(1,buf_filter);
   SetIndexStyle(1,DRAW_LINE,STYLE_SOLID,2,clrYellow);
   
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
   double f_alpha,f_beta,f_c1,f_c2,f_c3;      
//--------------------------------------------------------------------

   i_countedBars=IndicatorCounted();    // Number of counted bars
   i_limit=Bars-i_countedBars-1;              // Index of the 1st uncounted
   if (i_limit>i_history-1) {                   // If too many bars ..
      i_limit=i_history-1;                     // ..calculate for specified amount.
   }
   
   for (i=i_limit; i>=0;i--) {                                 // >= calculates also current bar, > does not
      
      buf_price[i] = (high[i]+low[i]+close[i]+close[i])/4;  
      
      if ((i>=i_limit-2) && (i_limit>1)) {        // Initialize only at beggining, not at every live tick
         buf_filter[i] = buf_price[i];}
      else {
         f_alpha = MathExp(-1.414*M_PI/(double)i_period);
         f_beta = 2 * f_alpha * cos(1.414*M_PI/(double)i_period);
         f_c2 = f_beta;
         f_c3 = - f_alpha * f_alpha;
         f_c1 = 1 - f_c2 - f_c3;
         buf_filter[i] = (f_c1*(buf_price[i]+buf_price[i+1])/2) + f_c2*buf_filter[i+1] + f_c3*buf_filter[i+2]; 
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
