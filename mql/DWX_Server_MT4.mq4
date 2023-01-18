//+--------------------------------------------------------------+
//|     DWX_server_MT4.mq4
//|     @author: Darwinex Labs (www.darwinex.com)
//|
//|     Copyright (c) 2017-2021, Darwinex. All rights reserved.
//|    
//|     Licensed under the BSD 3-Clause License, you may not use this file except 
//|     in compliance with the License. 
//|    
//|     You may obtain a copy of the License at:    
//|     https://opensource.org/licenses/BSD-3-Clause
//+--------------------------------------------------------------+
#property copyright "Copyright 2017-2021, Darwinex Labs."
#property link      "https://www.darwinex.com/"
#property version   "1.0"
#property strict

input string t0 = "--- General Parameters ---";
// if the timer is too small, we might have problems accessing the files from python (mql will write to file every update time). 
input int MILLISECOND_TIMER = 25;

input int numLastMessages = 50;
input string t1 = "If true, it will open charts for bar data symbols, ";
input string t2 = "which reduces the delay on a new bar.";
input bool openChartsForBarData = true;
input bool openChartsForHistoricData = true;
input string t3 = "--- Trading Parameters ---";
input int MaximumOrders = 1;
input double MaximumLotSize = 0.01;
input int SlippagePoints = 3;
input int lotSizeDigits = 2;

int maxCommandFiles = 50;
int maxNumberOfCharts = 100;

long lastMessageMillis = 0;
long lastUpdateMillis = GetTickCount(), lastUpdateOrdersMillis = GetTickCount();

string startIdentifier = "<:";
string endIdentifier = ":>";
string delimiter = "|";
string folderName = "DWX";
string filePathOrders = folderName + "/DWX_Orders.txt";
string filePathMessages = folderName + "/DWX_Messages.txt";
string filePathMarketData = folderName + "/DWX_Market_Data.txt";
string filePathBarData = folderName + "/DWX_Bar_Data.txt";
string filePathHistoricData = folderName + "/DWX_Historic_Data.txt";
string filePathHistoricTrades = folderName + "/DWX_Historic_Trades.txt";
string filePathCommandsPrefix = folderName + "/DWX_Commands_";

string lastOrderText = "", lastMarketDataText = "", lastMessageText = "";

struct MESSAGE
{
   long millis;
   string message;
};

MESSAGE lastMessages[];

string MarketDataSymbols[];

int commandIDindex = 0;
int commandIDs[];

/**
 * Class definition for an specific instrument: the tuple (symbol,timeframe)
 */
class Instrument {
public:  
    
   //--------------------------------------------------------------
   /** Instrument constructor */
   Instrument() { _symbol = ""; _name = ""; _timeframe = PERIOD_CURRENT; _lastPubTime =0;}    
     
   //--------------------------------------------------------------
   /** Getters */
   string          symbol()    { return _symbol; }
   ENUM_TIMEFRAMES timeframe() { return _timeframe; }
   string          name()      { return _name; }
   datetime        getLastPublishTimestamp() { return _lastPubTime; }
   /** Setters */
   void            setLastPublishTimestamp(datetime tmstmp) { _lastPubTime = tmstmp; }
   
   //--------------------------------------------------------------
   /** Setup instrument with symbol and timeframe descriptions
   *  @param argSymbol Symbol
   *  @param argTimeframe Timeframe
   */
   void setup(string argSymbol, string argTimeframe) {
      _symbol = argSymbol;
      _timeframe = StringToTimeFrame(argTimeframe);
      _name  = _symbol + "_" + argTimeframe;
      _lastPubTime = 0;
      SymbolSelect(_symbol, true);
      if (openChartsForBarData) {
         OpenChartIfNotOpen(_symbol, _timeframe);
         Sleep(200);  // sleep to allow time to open the chart and update the data. 
      }
   }
    
   //--------------------------------------------------------------
   /** Get last N MqlRates from this instrument (symbol-timeframe)
   *  @param rates Receives last 'count' rates
   *  @param count Number of requested rates
   *  @return Number of returned rates
   */
   int GetRates(MqlRates& rates[], int count) {
      // ensures that symbol is setup
      if(StringLen(_symbol) > 0) 
         return CopyRates(_symbol, _timeframe, 1, count, rates);
      return 0;
   }
    
protected:
   string _name;                //!< Instrument descriptive name
   string _symbol;              //!< Symbol
   ENUM_TIMEFRAMES _timeframe;  //!< Timeframe
   datetime _lastPubTime;     //!< Timestamp of the last published OHLC rate. Default = 0 (1 Jan 1970)
};

// Array of instruments whose rates will be published if Publish_MarketRates = True. It is initialized at OnInit() and
// can be updated through TRACK_RATES request from client peers.
Instrument BarDataInstruments[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {

   if (!EventSetMillisecondTimer(MILLISECOND_TIMER)) {
      Print("EventSetMillisecondTimer() returned an error: ", ErrorDescription(GetLastError()));
      return INIT_FAILED;
   }
   ResetFolder();
   ResetCommandIDs();
   ArrayResize(lastMessages, numLastMessages);
   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {

   EventKillTimer();
   
   ResetFolder();
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer() {
   
   // update prices regularly in case there was no tick within X milliseconds (for non-chart symbols). 
   if (GetTickCount() >= lastUpdateMillis + MILLISECOND_TIMER) OnTick();
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick() {
   /*
      Use this OnTick() function to send market data to subscribed client.
   */
   lastUpdateMillis = GetTickCount();
   
   CheckCommands();             
   CheckOpenOrders();
   CheckMarketData();
   CheckBarData();
}


void CheckCommands() {
   for (int i=0; i<maxCommandFiles; i++) {
      string filePath = filePathCommandsPrefix + IntegerToString(i) + ".txt";
      if (!FileIsExist(filePath)) return;
      int handle = FileOpen(filePath, FILE_READ|FILE_TXT);  // FILE_COMMON | 
      // Print(filePath, " | handle: ", handle);
      if (handle == -1) return;
      if (handle == 0) return;
      
      string text = "";
      while(!FileIsEnding(handle)) text += FileReadString(handle);
      FileClose(handle);
      for (int j=0; j<10; j++) if (FileDelete(filePath)) break;
      
      // make sure that the file content is complete. 
      int length = StringLen(text);
      if (StringSubstr(text, 0, 2) != startIdentifier) {
         SendError("WRONG_FORMAT_START_IDENTIFIER", "Start identifier not found for command: " + text);
         return;
      }
      
      if (StringSubstr(text, length-2, 2) != endIdentifier) {
         SendError("WRONG_FORMAT_END_IDENTIFIER", "End identifier not found for command: " + text);
         return;
      }
      text = StringSubstr(text, 2, length-4);
      
      ushort uSep = StringGetCharacter(delimiter, 0);
      string data[];
      int splits = StringSplit(text, uSep, data);
      
      if (splits != 3) {
         SendError("WRONG_FORMAT_COMMAND", "Wrong format for command: " + text);
         return;
      }
      
      int commandID = (int)data[0];
      string command = data[1];
      string content = data[2];
      // Print(StringFormat("commandID: %d, command: %s, content: %s ", commandID, command, content));
      
      // dont check commandID for the reset command because else it could get blocked if only the python/java/dotnet side restarts, but not the mql side.
      if (command != "RESET_COMMAND_IDS" && CommandIDfound(commandID)) {
         Print(StringFormat("Not executing command because ID already exists. commandID: %d, command: %s, content: %s ", commandID, command, content));
         return;
      }
      commandIDs[commandIDindex] = commandID;
      commandIDindex = (commandIDindex + 1) % ArraySize(commandIDs);
      
      if (command == "OPEN_ORDER") {
         OpenOrder(content);
      } else if (command == "CLOSE_ORDER") {
         CloseOrder(content);
      } else if (command == "CLOSE_ALL_ORDERS") {
         CloseAllOrders();
      } else if (command == "CLOSE_ORDERS_BY_SYMBOL") {
         CloseOrdersBySymbol(content);
      } else if (command == "CLOSE_ORDERS_BY_MAGIC") {
         CloseOrdersByMagic(content);
      } else if (command == "MODIFY_ORDER") {
         ModifyOrder(content);
      } else if (command == "SUBSCRIBE_SYMBOLS") {
         SubscribeSymbols(content);
      } else if (command == "SUBSCRIBE_SYMBOLS_BAR_DATA") {
         SubscribeSymbolsBarData(content);
      } else if (command == "GET_HISTORIC_TRADES") {
         GetHistoricTrades(content);
      } else if (command == "GET_HISTORIC_DATA") {
         GetHistoricData(content);
      } else if (command == "RESET_COMMAND_IDS") {
         Print("Resetting stored command IDs.");
         ResetCommandIDs();
      }
   }
}


void OpenOrder(string orderStr) {
   
   string sep = ",";
   ushort uSep = StringGetCharacter(sep, 0);
   string data[];
   int splits = StringSplit(orderStr, uSep, data);
   
   if (ArraySize(data) != 9) {
      SendError("OPEN_ORDER_WRONG_FORMAT", "Wrong format for OPEN_ORDER command: " + orderStr);
      return;
   }
   
   int numOrders = NumOrders();
   if (numOrders >= MaximumOrders) {
      SendError("OPEN_ORDER_MAXIMUM_NUMBER", StringFormat("Number of orders (%d) larger than or equal to MaximumOrders (%d).", numOrders, MaximumOrders));
      return;
   }
   
   string symbol = data[0];
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   int orderType = StringToOrderType(data[1]);
   double lots = NormalizeDouble(StringToDouble(data[2]), lotSizeDigits);
   double price = NormalizeDouble(StringToDouble(data[3]), digits);
   double stopLoss = NormalizeDouble(StringToDouble(data[4]), digits);
   double takeProfit = NormalizeDouble(StringToDouble(data[5]), digits);
   int magic = (int)StringToInteger(data[6]);
   string comment = data[7];
   datetime expiration = (datetime)StringToInteger(data[8]);
   
   if (price == 0 && orderType == OP_BUY) price = MarketInfo(symbol, MODE_ASK);
   if (price == 0 && orderType == OP_SELL) price = MarketInfo(symbol, MODE_BID);
   
   if (orderType == -1) {
      SendError("OPEN_ORDER_TYPE", StringFormat("Order type could not be parsed: %f (%f)", orderType, data[1]));
      return;
   }
   
   if (lots < MarketInfo(symbol, MODE_MINLOT) || lots > MarketInfo(symbol, MODE_MAXLOT)) {
      SendError("OPEN_ORDER_LOTSIZE_OUT_OF_RANGE", StringFormat("Lot size out of range (min: %f, max: %f): %f", MarketInfo(symbol, MODE_MINLOT), MarketInfo(symbol, MODE_MAXLOT), lots));
      return;
   }
   
   if (lots > MaximumLotSize) {
      SendError("OPEN_ORDER_LOTSIZE_TOO_LARGE", StringFormat("Lot size (%.2f) larger than MaximumLotSize (%.2f).", lots, MaximumLotSize));
      return;
   }
   
   if (price == 0) {
      SendError("OPEN_ORDER_PRICE_ZERO", "Price is zero: " + orderStr);
      return;
   }
   
   int ticket = OrderSend(symbol, orderType, lots, price, SlippagePoints, stopLoss, takeProfit, comment, magic, expiration);
   if (ticket >= 0) {
      SendInfo("Successfully sent order " + IntegerToString(ticket) + ": " + symbol + ", " + OrderTypeToString(orderType) + ", " + DoubleToString(lots, lotSizeDigits) + ", " + DoubleToString(price, digits));
   } else {
      SendError("OPEN_ORDER", "Could not open order: " + ErrorDescription(GetLastError()));
   }
}

void ModifyOrder(string orderStr) {
   string sep = ",";
   ushort uSep = StringGetCharacter(sep, 0);
   string data[];
   int splits = StringSplit(orderStr, uSep, data);
   
   if (ArraySize(data) != 6) {
      SendError("MODIFY_ORDER_WRONG_FORMAT", "Wrong format for MODIFY_ORDER command: " + orderStr);
      return;
   }
   
   int ticket = (int)StringToInteger(data[0]);
   
   if (!OrderSelect(ticket, SELECT_BY_TICKET)) {
      SendError("MODIFY_ORDER_SELECT_TICKET", "Could not select order with ticket: " + IntegerToString(ticket));
      return;
   }
   
   int digits = (int)MarketInfo(OrderSymbol(), MODE_DIGITS);
   
   double lots = NormalizeDouble(StringToDouble(data[1]), lotSizeDigits);
   double price = NormalizeDouble(StringToDouble(data[2]), digits);
   double stopLoss = NormalizeDouble(StringToDouble(data[3]), digits);
   double takeProfit = NormalizeDouble(StringToDouble(data[4]), digits);
   datetime expiration = (datetime)StringToInteger(data[5]);
   
   if (price == 0) price = OrderOpenPrice();
   
   if (lots < MarketInfo(OrderSymbol(), MODE_MINLOT) || lots > MarketInfo(OrderSymbol(), MODE_MAXLOT)) {
      SendError("MODIFY_ORDER_LOTSIZE_OUT_OF_RANGE", StringFormat("Lot size out of range (min: %f, max: %f): %f", MarketInfo(OrderSymbol(), MODE_MINLOT), MarketInfo(OrderSymbol(), MODE_MAXLOT), lots));
      return;
   }
   
   bool res = OrderModify(ticket, price, stopLoss, takeProfit, expiration);
   if (res) {
      SendInfo(StringFormat("Successfully modified order %d: %s, %s, %.2f, %.5f, %.5f, %.5f", ticket, OrderSymbol(), OrderTypeToString(OrderType()), lots, price, stopLoss, takeProfit));
   } else {
      SendError("MODIFY_ORDER", StringFormat("Error in modifying order %d: %s", ticket, ErrorDescription(GetLastError())));
   }
}


void CloseOrder(string orderStr) {
   string sep = ",";
   ushort uSep = StringGetCharacter(sep, 0);
   string data[];
   int splits = StringSplit(orderStr, uSep, data);
   
   if (ArraySize(data) != 2) {
      SendError("CLOSE_ORDER_WRONG_FORMAT", "Wrong format for CLOSE_ORDER command: " + orderStr);
      return;
   }
   int ticket = (int)StringToInteger(data[0]);
   double lots = NormalizeDouble(StringToDouble(data[1]), lotSizeDigits);
   
   if (!OrderSelect(ticket, SELECT_BY_TICKET)) {
      SendError("CLOSE_ORDER_SELECT_TICKET", "Could not select order with ticket: " + IntegerToString(ticket));
      return;
   }
   
   bool res = false;
   if (OrderType() == OP_BUY || OrderType() == OP_SELL) {
       if (lots == 0) lots = OrderLots();
       res = OrderClose(ticket, lots, OrderClosePrice(), SlippagePoints);
   } else {
      res = OrderDelete(ticket);
   }
   
   if (res) {
      SendInfo("Successfully closed order: " + IntegerToString(ticket) + ", " + OrderSymbol() + ", " + DoubleToString(lots, lotSizeDigits));
   } else {
      SendError("CLOSE_ORDER_TICKET", "Could not close position " + IntegerToString(ticket) + ": " + ErrorDescription(GetLastError()));
   }
}


void CloseAllOrders() {
   
   int closed = 0, errors = 0;

   for(int i=OrdersTotal()-1; i>=0; i--) {
   
      if (!OrderSelect(i,SELECT_BY_POS)) continue;
      
      if (OrderType() == OP_BUY || OrderType() == OP_SELL) {
         bool res = OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), SlippagePoints);
         if (res) 
            closed++;
         else 
            errors++;         
      } else if (OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT || OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP) {
         bool res = OrderDelete(OrderTicket());
         if (res) 
            closed++;
         else 
            errors++; 
      }
   }
   
   if (closed == 0 && errors == 0) 
      SendInfo("No orders to close.");
   if (errors > 0) 
      SendError("CLOSE_ORDER_ALL", "Error during closing of " + IntegerToString(errors) + " orders.");
   else
      SendInfo("Successfully closed " + IntegerToString(closed) + " orders.");
}


void CloseOrdersBySymbol(string symbol) {
   
   int closed = 0, errors = 0;

   for(int i=OrdersTotal()-1; i>=0; i--) {
   
      if (!OrderSelect(i,SELECT_BY_POS) || OrderSymbol() != symbol) continue;
      
      if (OrderType() == OP_BUY || OrderType() == OP_SELL) {
         bool res = OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), SlippagePoints);
         if (res) 
            closed++;
         else 
            errors++;         
      } else if (OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT || OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP) {
         bool res = OrderDelete(OrderTicket());
         if (res) 
            closed++;
         else 
            errors++; 
      }
   }
   
   if (closed == 0 && errors == 0) 
      SendInfo("No orders to close with symbol " + symbol + ".");
   else if (errors > 0) 
      SendError("CLOSE_ORDER_SYMBOL", "Error during closing of " + IntegerToString(errors) + " orders with symbol " + symbol + ".");
   else
      SendInfo("Successfully closed " + IntegerToString(closed) + " orders with symbol " + symbol + ".");
}


void CloseOrdersByMagic(string magicStr) {
   
   int magic = (int)StringToInteger(magicStr);
   
   int closed = 0, errors = 0;

   for(int i=OrdersTotal()-1; i>=0; i--) {
   
      if (!OrderSelect(i,SELECT_BY_POS) || OrderMagicNumber() != magic) continue;
      
      if (OrderType() == OP_BUY || OrderType() == OP_SELL) {
         bool res = OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), SlippagePoints);
         if (res) 
            closed++;
         else 
            errors++;         
      } else if (OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT 
                 || OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP) {
         bool res = OrderDelete(OrderTicket());
         if (res) 
            closed++;
         else 
            errors++; 
      }
   }
   
   if (closed == 0 && errors == 0) 
      SendInfo("No orders to close with magic " + IntegerToString(magic) + ".");
   else if (errors > 0) 
      SendError("CLOSE_ORDER_MAGIC", "Error during closing of " + IntegerToString(errors) + " orders with magic " + IntegerToString(magic) + ".");
   else
      SendInfo("Successfully closed " + IntegerToString(closed) + " orders with magic " + IntegerToString(magic) + ".");
   
}


int NumOrders() {
   
   int n = 0;

   for(int i=OrdersTotal()-1; i>=0; i--) {
   
      if (!OrderSelect(i,SELECT_BY_POS)) continue;
      
      if (OrderType() == OP_BUY || OrderType() == OP_SELL 
          || OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT 
          || OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP) {
         n++;
      }
   }
   return n;
}


void SubscribeSymbols(string symbolsStr) {
   
   string sep = ",";
   ushort uSep = StringGetCharacter(sep, 0);
   string data[];
   int splits = StringSplit(symbolsStr, uSep, data);
   
   string successSymbols = "", errorSymbols = "";
   
   if (ArraySize(data) == 0) {
      ArrayResize(MarketDataSymbols, 0);
      SendInfo("Unsubscribed from all tick data because of empty symbol list.");
      return;
   }
   
   for(int i=0; i<ArraySize(data); i++) {
      if (SymbolSelect(data[i], true)) {
         ArrayResize(MarketDataSymbols, i+1);
         MarketDataSymbols[i] = data[i];
         successSymbols += data[i] + ", ";
      } else {
         errorSymbols += data[i] + ", ";
      }
   }
   
   if (StringLen(errorSymbols) > 0) {
      SendError("SUBSCRIBE_SYMBOL", "Could not subscribe to symbols: " + StringSubstr(errorSymbols, 0, StringLen(errorSymbols)-2));
   }
   if (StringLen(successSymbols) > 0) {
      SendInfo("Successfully subscribed to: " + StringSubstr(successSymbols, 0, StringLen(successSymbols)-2));
   }
}


void SubscribeSymbolsBarData(string dataStr) {

   string sep = ",";
   ushort uSep = StringGetCharacter(sep, 0);
   string data[];
   int splits = StringSplit(dataStr, uSep, data);
   
   if (ArraySize(data) == 0) {
      ArrayResize(BarDataInstruments, 0);
      SendInfo("Unsubscribed from all bar data because of empty symbol list.");
      return;
   }
   
   if (ArraySize(data) < 2 || ArraySize(data) % 2 != 0) {
      SendError("BAR_DATA_WRONG_FORMAT", "Wrong format to subscribe to bar data: " + dataStr);
      return;
   }
   
   // Format: SYMBOL_1,TIMEFRAME_1,SYMBOL_2,TIMEFRAME_2,...,SYMBOL_N,TIMEFRAME_N
   string errorSymbols = "";
   
   int numInstruments = ArraySize(data)/2;
   
   for(int s=0; s<numInstruments; s++) {
   
      if (SymbolSelect(data[2*s], true)) {
         
         ArrayResize(BarDataInstruments, s+1);
         
         BarDataInstruments[s].setup(data[2*s], data[(2*s)+1]);
         
      } else {
         errorSymbols += "'" + data[2*s] + "', ";
      }
   }
   
   if (StringLen(errorSymbols) > 0)
      errorSymbols = "[" + StringSubstr(errorSymbols, 0, StringLen(errorSymbols)-2) + "]";
   
   if (StringLen(errorSymbols) == 0) {
      SendInfo("Successfully subscribed to bar data: " + dataStr);
      CheckBarData();
   } else {
      SendError("SUBSCRIBE_BAR_DATA", "Could not subscribe to bar data for: " + errorSymbols);
   }
}


void GetHistoricData(string dataStr) {
   
   string sep = ",";
   ushort uSep = StringGetCharacter(sep, 0);
   string data[];
   int splits = StringSplit(dataStr, uSep, data);
   
   if (ArraySize(data) != 4) {
      SendError("HISTORIC_DATA_WRONG_FORMAT", "Wrong format for GET_HISTORIC_DATA command: " + dataStr);
      return;
   }
   
   string symbol = data[0];
   ENUM_TIMEFRAMES timeFrame = StringToTimeFrame(data[1]);
   datetime dateStart = (datetime)StringToInteger(data[2]);
   datetime dateEnd = (datetime)StringToInteger(data[3]);
   
   if (StringLen(symbol) == 0) {
      SendError("HISTORIC_DATA_SYMBOL", "Could not read symbol: " + dataStr);
      return;
   }
   
   if (!SymbolSelect(symbol, true)) {
      SendError("HISTORIC_DATA_SELECT_SYMBOL", "Could not select symbol " + symbol + " in market watch. Error: " + ErrorDescription(GetLastError()));
   }
   
   if (openChartsForHistoricData) {
      // if just opnened sleep to give MT4 some time to fetch the data. 
      if (OpenChartIfNotOpen(symbol, timeFrame)) Sleep(200);
   }
   
   MqlRates rates_array[];
      
   // Get prices
   int rates_count = 0;
   
   // Handling ERR_HISTORY_WILL_UPDATED (4066) and ERR_NO_HISTORY_DATA (4073) errors. 
   // For non-chart symbols and time frames MT4 often needs a few requests until the data is available. 
   // But even after 10 requests it can happen that it is not available. So it is best to have the charts open. 
   for (int i=0; i<10; i++) {
      // if (numBars > 0)
      //   rates_count = CopyRates(symbol, timeFrame, startPos, numBars, rates_array);
      rates_count = CopyRates(symbol, timeFrame, dateStart, dateEnd, rates_array);
      int errorCode = GetLastError();
      // Print("errorCode: ", errorCode);
      if (rates_count > 0 || (errorCode != 4066 && errorCode != 4073)) break;
      Sleep(200);
   }
   
   if (rates_count <= 0) {
      SendError("HISTORIC_DATA", "Could not get historic data for " + symbol + "_" + data[1] + ": " + ErrorDescription(GetLastError()));
      return;
   }
   
   bool first = true;
   string text = "{\"" + symbol + "_" + TimeFrameToString(timeFrame) + "\": {";
   
   for(int i=0; i<rates_count; i++) {
      
      if (first) {
         double daysDifference = ((double)MathAbs(rates_array[i].time - dateStart)) / (24 * 60 * 60);
         if ((timeFrame == PERIOD_MN1 && daysDifference > 33) || (timeFrame == PERIOD_W1 && daysDifference > 10) || (timeFrame < PERIOD_W1 && daysDifference > 3)) {
            SendInfo(StringFormat("The difference between requested start date and returned start date is relatively large (%.1f days). Maybe the data is not available on MetaTrader.", daysDifference));
         }
         // Print(dateStart, " | ", rates_array[i].time, " | ", daysDifference);
      } else {
         text += ", ";
      }
      
      // maybe use integer instead of time string? IntegerToString(rates_array[i].time)
      text += StringFormat("\"%s\": {\"open\": %.5f, \"high\": %.5f, \"low\": %.5f, \"close\": %.5f, \"tick_volume\": %.5f}", 
                           TimeToString(rates_array[i].time), 
                           rates_array[i].open, 
                           rates_array[i].high, 
                           rates_array[i].low, 
                           rates_array[i].close, 
                           rates_array[i].tick_volume);
      
      first = false;
   }
   
   text += "}}";
   for (int i=0; i<5; i++) {
      if (WriteToFile(filePathHistoricData, text)) break;
      Sleep(100);
   }
   SendInfo(StringFormat("Successfully read historic data for %s_%s.", symbol, data[1]));
}


void GetHistoricTrades(string dataStr) {

   int lookbackDays = (int)StringToInteger(dataStr);
   
   if (lookbackDays <= 0) {
      SendError("HISTORIC_TRADES", "Lookback days smaller or equal to zero: " + dataStr);
      return;
   }
   
   bool first = true;
   string text = "{";
   for(int i=OrdersHistoryTotal()-1; i>=0; i--) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if (OrderOpenTime() < TimeCurrent() - lookbackDays * (24 * 60 * 60)) continue;
      if (!first) text += ", ";
      else first = false;
      text += StringFormat("\"%d\": {\"magic\": %d, \"symbol\": \"%s\", \"lots\": %.2f, \"type\": \"%s\", \"open_time\": \"%s\", \"close_time\": \"%s\", \"open_price\": %.5f, \"close_price\": %.5f, \"SL\": %.5f, \"TP\": %.5f, \"pnl\": %.2f, \"commission\": %.2f, \"swap\": %.2f, \"comment\": \"%s\"}", 
                           OrderTicket(), 
                           OrderMagicNumber(), 
                           OrderSymbol(), 
                           OrderLots(), 
                           OrderTypeToString(OrderType()), 
                           TimeToString(OrderOpenTime(), TIME_DATE|TIME_SECONDS), 
                           TimeToString(OrderCloseTime(), TIME_DATE|TIME_SECONDS), 
                           OrderOpenPrice(), 
                           OrderClosePrice(), 
                           OrderStopLoss(), 
                           OrderTakeProfit(), 
                           OrderProfit(), 
                           OrderCommission(), 
                           OrderSwap(), 
                           OrderComment());
   }
   text += "}";
   for (int i=0; i<5; i++) {
      if (WriteToFile(filePathHistoricTrades, text)) break;
      Sleep(100);
   }
   SendInfo("Successfully read historic trades.");
}


void CheckMarketData() {
   
   bool first = true;
   string text = "{";
   for(int i=0; i<ArraySize(MarketDataSymbols); i++) {
      
      MqlTick lastTick;
   
      if(SymbolInfoTick(MarketDataSymbols[i], lastTick)) {
         
         if (!first)
            text += ", ";
         
         text += StringFormat("\"%s\": {\"bid\": %.5f, \"ask\": %.5f, \"tick_value\": %.5f}", 
                              MarketDataSymbols[i], 
                              lastTick.bid, 
                              lastTick.ask,
                              MarketInfo(MarketDataSymbols[i], MODE_TICKVALUE));
         
         first = false;
      } else {
         SendError("GET_BID_ASK", "Could not get bid/ask for " + MarketDataSymbols[i] + ". Last error: " + ErrorDescription(GetLastError()));
      }
   }
   
   text += "}";
   
   // only write to file if there was a change. 
   if (text == lastMarketDataText) return;
   if (WriteToFile(filePathMarketData, text)) {
      lastMarketDataText = text;
   }
}


void CheckBarData() {
   
   // Python clients can also subscribe to a rates feed for each tracked instrument
   
   bool newData = false;
   string text = "{";
   
   for(int s = 0; s < ArraySize(BarDataInstruments); s++) {
      
      MqlRates curr_rate[];
      
      int count = BarDataInstruments[s].GetRates(curr_rate, 1);
      // if last rate is returned and its timestamp is greater than the last published...
      if(count > 0 && curr_rate[0].time > BarDataInstruments[s].getLastPublishTimestamp()) {
         
         string rates = StringFormat("\"%s\": {\"time\": \"%s\", \"open\": %f, \"high\": %f, \"low\": %f, \"close\": %f, \"tick_volume\":%d}, ", 
                                     BarDataInstruments[s].name(), 
                                     TimeToString(curr_rate[0].time), 
                                     curr_rate[0].open, 
                                     curr_rate[0].high, 
                                     curr_rate[0].low, 
                                     curr_rate[0].close, 
                                     curr_rate[0].tick_volume);
         text += rates;
         newData = true;
         
         // updates the timestamp
         BarDataInstruments[s].setLastPublishTimestamp(curr_rate[0].time);
      
      }
   }
   if (!newData) return;
   
   text = StringSubstr(text, 0, StringLen(text)-2) + "}";
   for (int i=0; i<5; i++) {
      if (WriteToFile(filePathBarData, text)) break;
      Sleep(100);
   }
}


ENUM_TIMEFRAMES StringToTimeFrame(string tf) {
    // Standard timeframes
    if (tf == "M1") return PERIOD_M1;
    if (tf == "M5") return PERIOD_M5;
    if (tf == "M15") return PERIOD_M15;
    if (tf == "M30") return PERIOD_M30;
    if (tf == "H1") return PERIOD_H1;
    if (tf == "H4") return PERIOD_H4;
    if (tf == "D1") return PERIOD_D1;
    if (tf == "W1") return PERIOD_W1;
    if (tf == "MN1") return PERIOD_MN1;
    return -1;
}

string TimeFrameToString(ENUM_TIMEFRAMES tf) {
    // Standard timeframes
    switch(tf) {
        case PERIOD_M1:    return "M1";
        case PERIOD_M5:    return "M5";
        case PERIOD_M15:   return "M15";
        case PERIOD_M30:   return "M30";
        case PERIOD_H1:    return "H1";
        case PERIOD_H4:    return "H4";
        case PERIOD_D1:    return "D1";
        case PERIOD_W1:    return "W1";
        case PERIOD_MN1:   return "MN1";
        default:           return "UNKNOWN";
    }
}


// counts the number of orders with a given magic number. currently not used. 
int NumOpenOrdersWithMagic(int _magic) {
   int n = 0;
   for(int i=OrdersTotal()-1; i >= 0; i--) {
      if (OrderSelect(i,SELECT_BY_POS)==true && OrderMagicNumber() == _magic) {
         n++;
      }
   }
   return n;
}

void CheckOpenOrders() {
   
   bool first = true;
   string text = StringFormat("{\"account_info\": {\"name\": \"%s\", \"number\": %d, \"currency\": \"%s\", \"leverage\": %d, \"free_margin\": %f, \"balance\": %f, \"equity\": %f}, \"orders\": {", 
                              AccountName(), AccountNumber(), AccountCurrency(), AccountLeverage(), AccountFreeMargin(), AccountBalance(), AccountEquity());
   
   for(int i=OrdersTotal()-1; i>=0; i--) {
   
      if (!OrderSelect(i,SELECT_BY_POS)) continue;
      
      if (!first)
         text += ", ";
      
      text += StringFormat("\"%d\": {\"magic\": %d, \"symbol\": \"%s\", \"lots\": %.2f, \"type\": \"%s\", \"open_price\": %.5f, \"open_time\": \"%s\", \"SL\": %.5f, \"TP\": %.5f, \"pnl\": %.2f, \"commission\": %.2f, \"swap\": %.2f, \"comment\": \"%s\"}", 
                           OrderTicket(), 
                           OrderMagicNumber(), 
                           OrderSymbol(), 
                           OrderLots(), 
                           OrderTypeToString(OrderType()), 
                           OrderOpenPrice(), 
                           TimeToString(OrderOpenTime(), TIME_DATE|TIME_SECONDS), 
                           OrderStopLoss(), 
                           OrderTakeProfit(), 
                           OrderProfit(), 
                           OrderCommission(), 
                           OrderSwap(), 
                           OrderComment());
      first = false;
   }
   text += "}}";
   
   // if there are open positions, it will almost always be different because of open profit/loss. 
   // update at least once per second in case there was a problem during writing. 
   if (text == lastOrderText && GetTickCount() < lastUpdateOrdersMillis + 1000) return;
   if (WriteToFile(filePathOrders, text)) {
      lastUpdateOrdersMillis = GetTickCount();
      lastOrderText = text;
   }
}


bool WriteToFile(string filePath, string text) {
   int handle = FileOpen(filePath, FILE_WRITE|FILE_TXT);  // FILE_COMMON | 
   if (handle == -1) return false;
   // even an empty string writes two bytes (line break). 
   uint numBytesWritten = FileWrite(handle, text);
   FileClose(handle);
   return numBytesWritten > 0;
}


void SendError(string errorType, string errorDescription) {
   Print("ERROR: " + errorType + " | " + errorDescription);
   string message = StringFormat("{\"type\": \"ERROR\", \"time\": \"%s %s\", \"error_type\": \"%s\", \"description\": \"%s\"}", 
                                 TimeToString(TimeGMT(), TIME_DATE), TimeToString(TimeGMT(), TIME_SECONDS), errorType, errorDescription);
   SendMessage(message);
}


void SendInfo(string message) {
   Print("INFO: " + message);
   message = StringFormat("{\"type\": \"INFO\", \"time\": \"%s %s\", \"message\": \"%s\"}", 
                          TimeToString(TimeGMT(), TIME_DATE), TimeToString(TimeGMT(), TIME_SECONDS), message);
   SendMessage(message);
}


void SendMessage(string message) {
   
   for (int i=ArraySize(lastMessages)-1; i>=1; i--) {
      lastMessages[i] = lastMessages[i-1];
   }
   
   lastMessages[0].millis = GetTickCount();
   // to make sure that every message has a unique number. 
   if (lastMessages[0].millis <= lastMessageMillis) lastMessages[0].millis = lastMessageMillis+1;
   lastMessageMillis = lastMessages[0].millis;
   lastMessages[0].message = message;
   
   bool first = true;
   string text = "{";
   for (int i=ArraySize(lastMessages)-1; i>=0; i--) {
      if (StringLen(lastMessages[i].message) == 0) continue;
      if (!first)
         text += ", ";
      text += "\"" + IntegerToString(lastMessages[i].millis) + "\": " + lastMessages[i].message;
      first = false;
   }
   text += "}";
   
   if (text == lastMessageText) return;
   if (WriteToFile(filePathMessages, text)) lastMessageText = text;
}


bool OpenChartIfNotOpen(string symbol, ENUM_TIMEFRAMES timeFrame) {

   // long currentChartID = ChartID();
   long chartID = ChartFirst();
   
   for(int i=0; i<maxNumberOfCharts; i++) {
      if (StringLen(ChartSymbol(chartID)) > 0) {
         if (ChartSymbol(chartID) == symbol && ChartPeriod(chartID) == timeFrame) {
            Print(StringFormat("Chart already open (%s, %s).", symbol, TimeFrameToString(timeFrame)));
            return false;
         }
      }
      chartID = ChartNext(chartID);
      if (chartID == -1) break;
   }
   // open chart if not yet opened. 
   long id = ChartOpen(symbol, timeFrame);
   if (id > 0) {
      Print(StringFormat("Chart opened (%s, %s).", symbol, TimeFrameToString(timeFrame)));
      return true;
   } else {
      SendError("OPEN_CHART", StringFormat("Could not open chart (%s, %s).", symbol, TimeFrameToString(timeFrame)));
      return false;
   }
}

void ResetCommandIDs() {
   ArrayResize(commandIDs, 1000);  // save the last 1000 command IDs.
   ArrayFill(commandIDs, 0, ArraySize(commandIDs), -1);  // fill with -1 so that 0 will not be blocked.
   commandIDindex = 0;
}

bool CommandIDfound(int id) {
   for (int i=0; i<ArraySize(commandIDs); i++) if (id == commandIDs[i]) return true;
   return false;
}

// use string so that we can have the same in MT5. 
string OrderTypeToString(int orderType) {
   if (orderType == OP_BUY) return "buy";
   if (orderType == OP_SELL) return "sell";
   if (orderType == OP_BUYLIMIT) return "buylimit";
   if (orderType == OP_SELLLIMIT) return "selllimit";
   if (orderType == OP_BUYSTOP) return "buystop";
   if (orderType == OP_SELLSTOP) return "sellstop";
   return "unknown";
}

int StringToOrderType(string orderTypeStr) {
   if (orderTypeStr == "buy") return OP_BUY;
   if (orderTypeStr == "sell") return OP_SELL;
   if (orderTypeStr == "buylimit") return OP_BUYLIMIT;
   if (orderTypeStr == "selllimit") return OP_SELLLIMIT;
   if (orderTypeStr == "buystop") return OP_BUYSTOP;
   if (orderTypeStr == "sellstop") return OP_SELLSTOP;
   return -1;
}

void ResetFolder() {
   //FolderDelete(folderName);  // does not always work. 
   FolderCreate(folderName);
   FileDelete(filePathMarketData);
   FileDelete(filePathBarData);
   FileDelete(filePathHistoricData);
   FileDelete(filePathOrders);
   FileDelete(filePathMessages);
   for (int i=0; i<maxCommandFiles; i++) {
      FileDelete(filePathCommandsPrefix + IntegerToString(i) + ".txt");
   }
}


string ErrorDescription(int errorCode) {
   string errorString;
   
   switch(errorCode)
     {
      //---- codes returned from trade server
      case 0:
      case 1:   errorString="no error";                                                  break;
      case 2:   errorString="common error";                                              break;
      case 3:   errorString="invalid trade parameters";                                  break;
      case 4:   errorString="trade server is busy";                                      break;
      case 5:   errorString="old version of the client terminal";                        break;
      case 6:   errorString="no connection with trade server";                           break;
      case 7:   errorString="not enough rights";                                         break;
      case 8:   errorString="too frequent requests";                                     break;
      case 9:   errorString="malfunctional trade operation (never returned error)";      break;
      case 64:  errorString="account disabled";                                          break;
      case 65:  errorString="invalid account";                                           break;
      case 128: errorString="trade timeout";                                             break;
      case 129: errorString="invalid price";                                             break;
      case 130: errorString="invalid stops";                                             break;
      case 131: errorString="invalid trade volume";                                      break;
      case 132: errorString="market is closed";                                          break;
      case 133: errorString="trade is disabled";                                         break;
      case 134: errorString="not enough money";                                          break;
      case 135: errorString="price changed";                                             break;
      case 136: errorString="off quotes";                                                break;
      case 137: errorString="broker is busy (never returned error)";                     break;
      case 138: errorString="requote";                                                   break;
      case 139: errorString="order is locked";                                           break;
      case 140: errorString="long positions only allowed";                               break;
      case 141: errorString="too many requests";                                         break;
      case 145: errorString="modification denied because order too close to market";     break;
      case 146: errorString="trade context is busy";                                     break;
      case 147: errorString="expirations are denied by broker";                          break;
      case 148: errorString="amount of open and pending orders has reached the limit";   break;
      case 149: errorString="hedging is prohibited";                                     break;
      case 150: errorString="prohibited by FIFO rules";                                  break;
      //---- mql4 errors
      case 4000: errorString="no error (never generated code)";                          break;
      case 4001: errorString="wrong function pointer";                                   break;
      case 4002: errorString="array index is out of range";                              break;
      case 4003: errorString="no memory for function call stack";                        break;
      case 4004: errorString="recursive stack overflow";                                 break;
      case 4005: errorString="not enough stack for parameter";                           break;
      case 4006: errorString="no memory for parameter string";                           break;
      case 4007: errorString="no memory for temp string";                                break;
      case 4008: errorString="not initialized string";                                   break;
      case 4009: errorString="not initialized string in array";                          break;
      case 4010: errorString="no memory for array\' string";                             break;
      case 4011: errorString="too long string";                                          break;
      case 4012: errorString="remainder from zero divide";                               break;
      case 4013: errorString="zero divide";                                              break;
      case 4014: errorString="unknown command";                                          break;
      case 4015: errorString="wrong jump (never generated error)";                       break;
      case 4016: errorString="not initialized array";                                    break;
      case 4017: errorString="dll calls are not allowed";                                break;
      case 4018: errorString="cannot load library";                                      break;
      case 4019: errorString="cannot call function";                                     break;
      case 4020: errorString="expert function calls are not allowed";                    break;
      case 4021: errorString="not enough memory for temp string returned from function"; break;
      case 4022: errorString="system is busy (never generated error)";                   break;
      case 4050: errorString="invalid function parameters count";                        break;
      case 4051: errorString="invalid function parameter value";                         break;
      case 4052: errorString="string function internal error";                           break;
      case 4053: errorString="some array error";                                         break;
      case 4054: errorString="incorrect series array using";                             break;
      case 4055: errorString="custom indicator error";                                   break;
      case 4056: errorString="arrays are incompatible";                                  break;
      case 4057: errorString="global variables processing error";                        break;
      case 4058: errorString="global variable not found";                                break;
      case 4059: errorString="function is not allowed in testing mode";                  break;
      case 4060: errorString="function is not confirmed";                                break;
      case 4061: errorString="send mail error";                                          break;
      case 4062: errorString="string parameter expected";                                break;
      case 4063: errorString="integer parameter expected";                               break;
      case 4064: errorString="double parameter expected";                                break;
      case 4065: errorString="array as parameter expected";                              break;
      case 4066: errorString="requested history data in update state";                   break;
      case 4099: errorString="end of file";                                              break;
      case 4100: errorString="some file error";                                          break;
      case 4101: errorString="wrong file name";                                          break;
      case 4102: errorString="too many opened files";                                    break;
      case 4103: errorString="cannot open file";                                         break;
      case 4104: errorString="incompatible access to a file";                            break;
      case 4105: errorString="no order selected";                                        break;
      case 4106: errorString="unknown symbol";                                           break;
      case 4107: errorString="invalid price parameter for trade function";               break;
      case 4108: errorString="invalid ticket";                                           break;
      case 4109: errorString="trade is not allowed in the expert properties";            break;
      case 4110: errorString="longs are not allowed in the expert properties";           break;
      case 4111: errorString="shorts are not allowed in the expert properties";          break;
      case 4200: errorString="object is already exist";                                  break;
      case 4201: errorString="unknown object property";                                  break;
      case 4202: errorString="object is not exist";                                      break;
      case 4203: errorString="unknown object type";                                      break;
      case 4204: errorString="no object name";                                           break;
      case 4205: errorString="object coordinates error";                                 break;
      case 4206: errorString="no specified subwindow";                                   break;
      default:   errorString="ErrorCode: " + IntegerToString(errorCode);
      }
   return(errorString);
}


void printArray(string &arr[]) {
   if (ArraySize(arr) == 0) Print("{}");
   string printStr = "{";
   int i;
   for (i=0; i<ArraySize(arr); i++) {
      if (i == ArraySize(arr)-1) printStr += arr[i];
      else printStr += arr[i] + ", ";
   }
   Print(printStr + "}");
}

//+------------------------------------------------------------------+
