//+--------------------------------------------------------------+
//|     DWX_ZeroMQ_Server_v2.0.1_RC8.mq4
//|     @author: Darwinex Labs (www.darwinex.com)
//|
//|     Copyright (c) 2017-2020, Darwinex. All rights reserved.
//|    
//|     Licensed under the BSD 3-Clause License, you may not use this file except 
//|     in compliance with the License. 
//|    
//|     You may obtain a copy of the License at:    
//|     https://opensource.org/licenses/BSD-3-Clause
//+--------------------------------------------------------------+
#property copyright "Copyright 2017-2020, Darwinex Labs."
#property link      "https://www.darwinex.com/"
#property version   "1.0"
#property strict

/*

this script will send 100 pending orders to compare the execution time to DWX_Connect. 

*/

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {

   int n = 100;
   double openPrice = Ask - 0.01;  // Ask - 0.01
   ENUM_ORDER_TYPE orderType = OP_BUYLIMIT;  // OP_BUYLIMIT
   
   long beforeOpen = GetTickCount();
   for (int i=0; i<n; i++) {
      bool res = OrderSend(Symbol(), orderType, 0.01, openPrice, 0, 0, 0);
   }
   
   double openDuration = ((double)GetTickCount() - beforeOpen)/n;
   
   long beforeModification = GetTickCount();
   for(int i=OrdersTotal()-1; i>=0; i--) {
      if (!OrderSelect(i,SELECT_BY_POS) || OrderType() != orderType) continue;
      bool res = OrderModify(OrderTicket(), OrderOpenPrice(), NormalizeDouble(openPrice-0.01, Digits), OrderTakeProfit(), OrderExpiration());
   }
   
   double modifyDuration = ((double)GetTickCount() - beforeModification)/n;
   
   long beforeClose = GetTickCount();
   for(int i=OrdersTotal()-1; i>=0; i--) {
      if (!OrderSelect(i,SELECT_BY_POS) || OrderType() != orderType) continue;
      if (OrderType() == OP_BUY || OrderType() == OP_SELL) {
         bool res = OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 50);
      } else if (OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT || OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP) {
         bool res = OrderDelete(OrderTicket());
      }
   }
   double closeDuration = ((double)GetTickCount() - beforeClose)/n;
   
   Print(StringFormat("Close duration: %.1f milliseconds per order", closeDuration));
   Print(StringFormat("Modify duration: %.1f milliseconds per order", modifyDuration));
   Print(StringFormat("Open duration: %.1f milliseconds per order", openDuration));
   
   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer() {
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick() {
}