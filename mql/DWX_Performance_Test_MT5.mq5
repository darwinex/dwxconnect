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

#include<Trade\Trade.mqh>
//--- object for performing trade operations
CTrade  trade;

bool first = true;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {

   trade.SetAsyncMode(false);
   trade.SetTypeFilling(ORDER_FILLING_RETURN);  // will fill the complete order, there are also FOK and IOC modes: ORDER_FILLING_FOK, ORDER_FILLING_IOC. 
   trade.LogLevel(LOG_LEVEL_ERRORS);  // else it will print a lot on tester. 
   
   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick() {
   if (first) {
      first = false;
      
      int n = 100;
      double openPrice = ask() - 0.01;  // ask() - 0.01
      
      long beforeOpen = GetTickCount();
      for (int i=0; i<n; i++) {
         bool res = trade.BuyLimit(0.01, openPrice, Symbol(), 0, 0, ORDER_TIME_GTC, 0, "");
         // bool res = trade.Buy(0.01, Symbol(), openPrice, 0, 0, "");
      }
      
      double openDuration = ((double)GetTickCount() - beforeOpen)/n;
      
      Sleep(2000);
      
      long beforeModification = GetTickCount();
      for (int i=OrdersTotal()-1; i>=0; i--) {
         ulong ticket = OrderGetTicket(i);
         if(!OrderSelect(ticket) || OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_BUY_LIMIT) continue;
         bool res = trade.OrderModify(ticket, OrderGetDouble(ORDER_PRICE_OPEN), NormalizeDouble(openPrice-0.01, Digits()), OrderGetDouble(ORDER_TP), ORDER_TIME_GTC, 0);
      }
      // for filled positions:
      // for (int i=PositionsTotal()-1; i>=0; i--) {
      //    ulong ticket = PositionGetTicket(i);
      //    if (!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
      //    bool res = trade.PositionModify(ticket, NormalizeDouble(openPrice-0.01, Digits()), PositionGetDouble(POSITION_TP ));
      // }
      
      double modifyDuration = ((double)GetTickCount() - beforeModification)/n;
      
      Sleep(2000);
      
      long beforeClose = GetTickCount();
      for (int i=OrdersTotal()-1; i>=0; i--) {
         ulong ticket = OrderGetTicket(i);
         if(!OrderSelect(ticket) || OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_BUY_LIMIT) continue;
         bool res = trade.OrderDelete(ticket);
      }
      // for filled positions:
      // for (int i=PositionsTotal()-1; i>=0; i--) {
      //    ulong ticket = PositionGetTicket(i);
      //    if (!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
      //    bool res = trade.PositionClose(ticket);
      // }
      
      double closeDuration = ((double)GetTickCount() - beforeClose)/n;
      
      Print(StringFormat("Close duration: %.1f milliseconds per order", closeDuration));
      Print(StringFormat("Modify duration: %.1f milliseconds per order", modifyDuration));
      Print(StringFormat("Open duration: %.1f milliseconds per order", openDuration));
   }
}

MqlTick tick;
double ask() {
   if(SymbolInfoTick(Symbol(), tick)) return tick.ask;
   return SymbolInfoDouble(Symbol(), SYMBOL_ASK);
}
