//
//  SlotAndTableControllerView.swift
//  AcresBLEDemo
//
//  Created by Jozo Mostarac on 29.07.2022..
//

import SwiftUI

struct SlotAndTableControllerView: View {
    @StateObject var viewModel = SlotAndTableControllerViewModel()
    
    var body: some View {
        ZStack {
            VStack {
                switch viewModel.state {
                case .disconnected:
                    VStack {
                        Spacer()
                        HStack {
                            Button {
                                viewModel.findDevice(.fund)
                            } label: {
                                Text("FUND")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .border(.black)
                            }
                            Button {
                                viewModel.findDevice(.cashout)
                            } label: {
                                Text("CASH OUT")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .border(.black)
                            }
                        }
                        .padding()
                        .frame(height: 200)
                    }
                case .scanning:
                    VStack {
                        ProgressView()
                        Text("Scanning for device...")
                        Text("Hold your phone close to the dealer's device.")
                    }
                case .working:
                    VStack {
                        ProgressView()
                        Text("Working on it...")
                    }
                case .fund:
                    VStack {
                        Button {
                            viewModel.fundTable(amount: 10)
                        } label: {
                            Text("FUND TABLE WITH AMOUNT: 10")
                                .padding()
                                .border(.black)
                        }
                    }
                case .funding:
                    VStack {
                        ProgressView()
                        Text("Funding in progres...")
                        Text("Please wait for the dealer confirmation.")
                    }
                case .funded:
                    VStack {
                        Image(systemName: "checkmark")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.green)
                        Text("Funding successful!")
                    }
                case .cashingOut:
                    VStack {
                        ProgressView()
                        Text("Cash out requested.")
                        if viewModel.connectedToTable {
                            Text("Please wait for the dealer to enter the amount...")
                            Button {
                                viewModel.cancelCashOut()
                            } label: {
                                Text("CANCEL")
                                    .padding()
                                    .border(.black)
                            }
                        }
                    }
                case .cashingOutConfirmation:
                    VStack {
                        Text("Do you want to cash out this amount:")
                        Text(String((viewModel.cashOutAmount ?? -1)))
                        HStack {
                            Button {
                                viewModel.acceptCashOut()
                            } label: {
                                Text("ACCEPT")
                                    .padding()
                                    .border(.black)
                            }
                            if viewModel.connectedToTable {
                                Button {
                                    viewModel.cancelCashOut()
                                } label: {
                                    Text("CANCEL")
                                        .padding()
                                        .border(.black)
                                }
                            }
                        }
                        .padding()
                    }
                case .cashedOut:
                    VStack {
                        Image(systemName: "bitcoinsign.circle")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.blue)
                        Text("Cashout successful!")
                    }
                case .cashOutCanceling:
                    VStack {
                        ProgressView()
                        Text("Canceling in progres...")
                    }
                case .cashOutCanceled:
                    VStack {
                        Image(systemName: "x.circle")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.red)
                        Text("Cashout cancelled!")
                    }
                }
            }
            VStack {
                ConnectedTitle(title: viewModel.sas)
                Spacer()
            }
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
        }
    }
}

struct ConnectedTitle: View {
    let title: String?
    
    var body: some View {
        if let title = title {
            HStack {
                Text("Connected to device:")
                    .padding(.trailing, 5)
                Text(title)
            }
            .padding()
        }
    }
}

struct SlotAndTableControllerView_Previews: PreviewProvider {
    static var previews: some View {
        SlotAndTableControllerView()
    }
}
