//
//  MainView.swift
//  AcresBLEDemo
//
//  Created by Jozo Mostarac on 28.07.2022..
//

import SwiftUI

struct MainView: View {
    @ObservedObject private var errorHandler = ErrorHandler.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 100) {
                NavigationLink {
                    CardControllerView()
                        .environmentObject(errorHandler)
                } label: {
                    Text("CardControllerView")
                        .padding()
                        .border(.gray)
                }
                NavigationLink {
                    SlotAndTableControllerView()
                        .environmentObject(errorHandler)
                } label: {
                    Text("SlotAndTableControllerView")
                        .padding()
                        .border(.gray)
                }
            }
            .navigationTitle("Pick one")
            .navigationBarHidden(true)
        }
        .alert(errorHandler.errorMessage ?? "", isPresented: $errorHandler.isErrorPresented, actions: {
            Button("OK", role: .cancel) { }
        })
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
