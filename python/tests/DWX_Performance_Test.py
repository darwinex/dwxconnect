
import sys
import json
from time import sleep
from threading import Thread
from os.path import join, exists
from traceback import print_exc
from random import random
from datetime import datetime, timedelta

sys.path.append('../')
from api.DWX_Client import DWX_Client


"""

Performance Test

This test will measure how long it takes to open, modify and close pending orders. 
It will open 100 pending orders and calculate the average durations. 

Please don't run this on your live account. 

The MT4/5 server must be initialized with MaximumOrders>=100. 


"""

class TickProcessor():

    def __init__(self, MT4_directory_path, 
                 sleep_delay=0.005,             # 5 ms for time.sleep()
                 max_retry_command_seconds=10,  # retry to send the commend for 10 seconds if not successful. 
                 verbose=True
                 ):

        self.last_open_time = datetime.utcnow()
        self.last_modification_time = datetime.utcnow()

        self.dwx = DWX_Client(self, MT4_directory_path, sleep_delay, 
                              max_retry_command_seconds, verbose=verbose)
        sleep(1)

        self.dwx.start()
        
        self.n = 100
        symbol = 'EURUSD'
        entry_price = 1.17

        self.test_started = False
        self.n_modified = 0
        self.dwx.close_all_orders()
        while(len(self.dwx.open_orders) != 0):
            # print(self.dwx.open_orders)
            sleep(1)

        self.test_started = True
        self.before_open = datetime.utcnow()
        self.open_duration = -100
        for i in range(self.n):
            self.dwx.open_order(symbol=symbol, order_type='buylimit', lots=0.01, price=entry_price)
        
        
        while(len(self.dwx.open_orders) < self.n):
            sleep(1)
        
        self.modify_duration = -100
        self.before_modification = datetime.utcnow()
        for ticket in self.dwx.open_orders.keys():
            self.dwx.modify_order(ticket, stop_loss=entry_price-0.01)
        
        sleep(1)

        self.before_close = datetime.utcnow()
        for ticket in self.dwx.open_orders.keys():
            self.dwx.close_order(ticket)
        

    def on_tick(self, symbol, bid, ask):

        now = datetime.utcnow()

        print('on_tick:', now, symbol, bid, ask)


    def on_bar_data(self, symbol, time_frame, time, open_price, high, low, close_price, tick_volume):
        
        print('on_bar_data:', symbol, time_frame, datetime.utcnow(), time, open_price, high, low, close_price)


    def on_historic_data(self, symbol, time_frame, data):
        
        # you can also access the historic data via self.dwx.historic_data. 
        print('historic_data:', symbol, time_frame, f'{len(data)} bars')


    def on_message(self, message):

        if message['type'] == 'ERROR':
            print(message['type'], '|', message['error_type'], '|', message['description'])
        elif message['type'] == 'INFO':
            print(message['type'], '|', message['message'])
            if 'modified' in message['message']:
                self.n_modified += 1
                if self.n_modified == self.n:
                    self.modify_duration = (datetime.utcnow() - self.before_modification).total_seconds()


    # triggers when an order is added or removed, not when only modified. 
    def on_order_event(self):
        
        print(f'on_order_event. open_orders: {len(self.dwx.open_orders)} open orders')

        if not self.test_started:
            return
        
        if len(self.dwx.open_orders) == self.n:
            self.open_duration = (datetime.utcnow() - self.before_open).total_seconds()
            
        elif len(self.dwx.open_orders) == 0:
            close_duration = (datetime.utcnow() - self.before_close).total_seconds()
            print(f'\nopen_duration: {1000*self.open_duration/self.n:.1f} milliseconds per order')
            print(f'modify_duration: {1000*self.modify_duration/self.n:.1f} milliseconds per order')
            print(f'close_duration: {1000*close_duration/self.n:.1f} milliseconds per order')


mt4_files_path = 'C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/3B534B10135CFEDF8CD1AAB8BD994B13/MQL4/Files/'
processor = TickProcessor(mt4_files_path)

while processor.dwx.ACTIVE:
    sleep(1)


