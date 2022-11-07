//
//  CardControllerView.swift
//  AcresBLEDemo
//
//  Created by Jozo Mostarac on 29.07.2022..
//

import SwiftUI
import AcresBLE

struct CardControllerView: View {
    @StateObject var viewModel = CardControllerViewModel()

    var body: some View {
        VStack(spacing: 50) {
            switch viewModel.state {
            case .removed:
                VStack {
                    Picker("Card Track", selection: $viewModel.cardTrack) {
                        ForEach(CardTrack.allCases, id: \.self) { cardTrack in
                            Text(cardTrack.name)
                        }
                    }.pickerStyle(SegmentedPickerStyle())
                        .padding()
                        .pickerStyle(.segmented)

                    TextField("Card ID", text: $viewModel.cardID)

                        .textFieldStyle(.roundedBorder)
                        .border(.black)
                        .padding()

                    Button {
                        viewModel.insertPlayerCard()
                    } label: {
                        Text("INSERT PLAYER CARD")
                            .padding()
                            .border(.black)
                    }
                }.padding()
            case .inserted:
                VStack {
                    Text("CARD INSERTED")
                        .foregroundColor(.green)
                        .bold()

                    Text("CARD ID: " + viewModel.cardID)
                    Text("Card Track " + viewModel.cardTrack.rawValue.description)

                    Button {
                        viewModel.removePlayerCard()
                    } label: {
                        Text("REMOVE PLAYER CARD")
                            .padding()
                            .border(.black)
                    }
                }
                .padding()
            case .inserting:
                ProgressView()
                VStack{
                    Text("Inserting card...")
                    Text("Hold your phone close to the card reader.")
                }
            case .removing:
                ProgressView()
                Text("Removing card...")
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }
}

struct CardControllerView_Previews: PreviewProvider {
    static var previews: some View {
        CardControllerView()
    }
}
