//--------------------------------------------------------------------
// openOrder.mq4 
//--------------------------------------------------------------- 1 --

#property script_show_confirm
#property script_show_inputs

int start()                       
  {
	 
	extern int ticket = 0;
	res = OrderSelect(ticket,SELECT_BY_TICKET);
	if (res) {
	  string name = OrderSymbol();
	  int orderType = OrderType(); 
	  string price;
	  if (orderType = OP_BUYLIMIT) {
	  	price = MarketInfo(name,MODE_ASK);		// if BUY use ASK
	  }
	  elseif (orderType = OP_SELLLIMIT) {
		price = MarketInfo(name,MODE_BID);
	  }
      	ticket=OrderSend(name,orderType,OrderLots(),price,10,OrderStopLoss(),OrderTakeProfit(),OrderComment(),OrderMagicNumber()); //Opening 
	}
	else { Alert("Ticket: ", ticket, " cannot be selected."); }


   return;                          
  }
//-------------------------------------------------------------- 10 --
