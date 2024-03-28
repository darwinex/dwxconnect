
import sys
import json
from time import sleep
from threading import Thread
from os.path import join, exists
from traceback import print_exc
from random import random
from datetime import datetime, timezone, timedelta

sys.path.append('../')
from api.dwx_client import dwx_client


"""

Example dwxconnect client to test subscribing to many pairs. 

"""

class TickProcessor():

    def __init__(self, MT4_directory_path, 
                 sleep_delay=0.005,             # 5 ms for time.sleep()
                 max_retry_command_seconds=10,  # retry to send the commend for 10 seconds if not successful. 
                 verbose=True
                 ):

        self.last_open_time = datetime.now(timezone.utc)
        self.last_modification_time = datetime.now(timezone.utc)

        self.dwx = dwx_client(self, MT4_directory_path, sleep_delay, 
                              max_retry_command_seconds, verbose=verbose)
        sleep(1)

        self.dwx.start()

        # loading 298 symbols from file:
        symbols_file = 'symbol_list.txt'

        with open(symbols_file, 'r') as f:
            self.symbols = json.loads(f.read())['symbols']
        if len(self.symbols) < 1:
            print('Could not load symbols.')
            exit()

        # for brokers with suffix:
        for i in range(len(self.symbols)):
            self.symbols[i] += '.h'

        # subscribing to 38 pairs. 
        # self.symbols = ["AUDCAD", "AUDCHF", "AUDJPY", "AUDNZD", "AUDUSD", "CADCHF", "CADJPY", "CHFJPY", 
        #                 "EURAUD", "EURCAD", "EURCHF", "EURGBP", "EURJPY", "EURMXN", "EURNZD", "EURTRY", 
        #                 "EURUSD", "GBPAUD", "GBPCAD", "GBPCHF", "GBPJPY", "GBPNZD", "GBPUSD", "NZDCAD", 
        #                 "NZDCHF", "NZDJPY", "NZDUSD",  "USDCAD", "USDCHF", "USDHKD", "USDJPY", "USDMXN", 
        #                 "USDNOK", "USDSEK", "USDSGD", "USDTRY", "XAGUSD", "XAUUSD"]

        self.n_ticks = 0
        self.start_time = datetime.now(timezone.utc)
        self.last_print_time = datetime.now(timezone.utc)

        print(f'Subscribing to {len(self.symbols)} symbols.')
        
        self.dwx.subscribe_symbols(self.symbols)
        

    def on_tick(self, symbol, bid, ask):

        now = datetime.now(timezone.utc)

        # print('on_tick:', now, symbol, bid, ask)

        self.n_ticks += 1

        # to compare this to MT4 we have to add code in the DWX_Server.mq4 file. 
        # also change to "if True" before remove the on_tick() call in dwx_client.py
        if now > self.last_print_time + timedelta(seconds=2):
            self.last_print_time = now
            print(symbol, '| ticks per second per symbol:', round(self.n_ticks / (now - self.start_time).total_seconds() / len(self.symbols), 1))


    def on_bar_data(self, symbol, time_frame, time, open_price, high, low, close_price, tick_volume):
        
        print('on_bar_data:', symbol, time_frame, datetime.now(timezone.utc), time, open_price, high, low, close_price)


    def on_historic_data(self, symbol, time_frame, data):
        
        # you can also access the historic data via self.dwx.historic_data. 
        print('historic_data:', symbol, time_frame, f'{len(data)} bars')

    def on_message(self, message):

        if message['type'] == 'ERROR':
            print(message['type'], '|', message['error_type'], '|', message['description'])
        elif message['type'] == 'INFO':
            print(message['type'], '|', message['message'])
            # if 'modified' in message['message']:
            #     self.n_modified += 1
            #     if self.n_modified == self.n:
            #         self.modify_duration = (datetime.now(timezone.utc) - self.before_modification).total_seconds()

    # triggers when an order is added or removed, not when only modified. 
    def on_order_event(self):
        
        print(f'on_order_event. open_orders: {len(self.dwx.open_orders)} open orders')
        

mt4_files_path = 'C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/3B534B10135CFEDF8CD1AAB8BD994B13/MQL4/Files/'
processor = TickProcessor(mt4_files_path)

while processor.dwx.ACTIVE:
    sleep(1)


