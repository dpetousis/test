//--------------------------------------------------------------------
// openOrder.mq4 
//--------------------------------------------------------------- 1 --
int start()                       
  {



	  int magic = 9999;
	  double slowFilter = -1.0;
	  double loss = 0;
	  double sequence = 0;
	  string name = "EURUSDpro";
	  int orderType = OP_BUYLIMIT; 		
	  double lots = 0.01;
	  double SL = 1.18;
	  double TP = 1.22;
	  string price = MarketInfo(name,MODE_ASK);		// if BUY use ASK
      string s_comment = StringConcatenate(IntegerToString(magic),"_",DoubleToStr(slowFilter,(int)MarketInfo(name,MODE_DIGITS)),"_",DoubleToStr(loss,2),"_",DoubleToStr(sequence,0));
	  ticket=OrderSend(name,orderType,lots,price,10,SL,TP,s_comment,magic); //Opening 
                                         


   return;                          
  }
//-------------------------------------------------------------- 10 --