//
//  CardControllerView.swift
//  AcresBLEDemo
//
//  Created by Jozo Mostarac on 29.07.2022..
//

import SwiftUI

struct CardControllerView: View {
    @StateObject var viewModel = CardControllerViewModel()
    
    var body: some View {
        VStack(spacing: 50) {
            switch viewModel.state {
            case .removed:
                Button {
                    viewModel.insertPlayerCard()
                } label: {
                    Text("INSERT PLAYER CARD")
                        .padding()
                        .border(.black)
                }
            case .inserted:
                Text("CARD INSERTED")
                    .foregroundColor(.green)
                    .bold()
                Button {
                    viewModel.removePlayerCard()
                } label: {
                    Text("REMOVE PLAYER CARD")
                        .padding()
                        .border(.black)
                }
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
