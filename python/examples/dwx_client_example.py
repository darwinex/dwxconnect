
import json
from time import sleep
from threading import Thread
from os.path import join, exists
from traceback import print_exc
from random import random
from datetime import datetime, timedelta

from api.dwx_client import dwx_client


"""

Example dwxconnect client in python


This example client will subscribe to tick data and bar data. It will also request historic data. 
if open_test_trades=True, it will also open trades. Please only run this on a demo account. 

"""

class tick_processor():

    def __init__(self, MT4_directory_path, 
                 sleep_delay=0.005,             # 5 ms for time.sleep()
                 max_retry_command_seconds=10,  # retry to send the commend for 10 seconds if not successful. 
                 verbose=True
                 ):

        # if true, it will randomly try to open and close orders every few seconds. 
        self.open_test_trades = False

        self.last_open_time = datetime.utcnow()
        self.last_modification_time = datetime.utcnow()

        self.dwx = dwx_client(self, MT4_directory_path, sleep_delay, 
                              max_retry_command_seconds, verbose=verbose)
        sleep(1)

        self.dwx.start()
        
        # account information is stored in self.dwx.account_info.
        print("Account info:", self.dwx.account_info)

        # subscribe to tick data:
        self.dwx.subscribe_symbols(['EURUSD', 'GBPUSD'])

        # subscribe to bar data:
        self.dwx.subscribe_symbols_bar_data([['EURUSD', 'M15'], ['GBPJPY', 'M5'], ['AUDCAD', 'M1']])

        # request historic data:
        end = datetime.utcnow()
        start = end - timedelta(days=30)  # last 30 days
        self.dwx.get_historic_data('EURUSD', 'D1', start.timestamp(), end.timestamp())


    def on_tick(self, symbol, bid, ask):

        now = datetime.utcnow()

        print('on_tick:', now, symbol, bid, ask)

        # to test trading. 
        # this will randomly tryp to open and close orders every few seconds. 
        if self.open_test_trades:
            if now > self.last_open_time + timedelta(seconds=3):

                self.last_open_time = now
                
                order_type = 'buy'
                price = ask
                if random() > 0.5:
                    order_type = 'sell'
                    price = bid

                self.dwx.open_order(symbol=symbol, order_type=order_type, 
                                    price=price, lots=0.5)

            if now > self.last_modification_time + timedelta(seconds=10):

                self.last_modification_time = now

                for ticket in self.dwx.open_orders.keys():
                    self.dwx.close_order(ticket, lots=0.1)

            if len(self.dwx.open_orders) >= 10:
                self.dwx.close_all_orders()
                # self.dwx.close_orders_by_symbol('GBPUSD')
                # self.dwx.close_orders_by_magic(0)


    def on_bar_data(self, symbol, time_frame, time, open_price, high, low, close_price, tick_volume):
        
        print('on_bar_data:', symbol, time_frame, datetime.utcnow(), time, open_price, high, low, close_price)

    
    def on_historic_data(self, symbol, time_frame, data):
        
        # you can also access the historic data via self.dwx.historic_data. 
        print('historic_data:', symbol, time_frame, f'{len(data)} bars')


    def on_historic_trades(self):

        print(f'historic_trades: {len(self.dwx.historic_trades)}')
    

    def on_message(self, message):

        if message['type'] == 'ERROR':
            print(message['type'], '|', message['error_type'], '|', message['description'])
        elif message['type'] == 'INFO':
            print(message['type'], '|', message['message'])


    # triggers when an order is added or removed, not when only modified. 
    def on_order_event(self):
        
        print(f'on_order_event. open_orders: {len(self.dwx.open_orders)} open orders')



MT4_files_dir = 'C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/3B534B10135CFEDF8CD1AAB8BD994B13/MQL4/Files/'

processor = tick_processor(MT4_files_dir)

while processor.dwx.ACTIVE:
    sleep(1)


