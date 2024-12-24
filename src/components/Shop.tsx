import React from 'react';
import { ShoppingBag } from 'lucide-react';

interface ShopProps {
  coins: number;
  onPurchase: (item: string) => void;
}

export default function Shop({ coins, onPurchase }: ShopProps) {
  const items = [
    { id: 'growth', name: 'Growth Pack', price: 50, icon: '📦' },
    { id: 'health', name: 'Health Pack', price: 30, icon: '💊' },
    { id: 'mood', name: 'Mood Pack', price: 20, icon: '🎈' },
  ];

  return (
    <div className="fixed top-4 right-4">
      <div className="relative group">
        <button className="bg-pink-500 p-3 rounded-full shadow-lg hover:bg-pink-600 transition-colors">
          <ShoppingBag className="w-6 h-6 text-white" />
        </button>
        
        <div className="absolute right-0 mt-2 w-64 bg-white rounded-xl shadow-xl opacity-0 scale-95 
          group-hover:opacity-100 group-hover:scale-100 transform transition-all origin-top-right">
          <div className="p-4">
            <div className="mb-3 text-center">
              <span className="text-lg font-semibold text-gray-700">🪙 {coins} Luna Coins</span>
            </div>
            
            <div className="space-y-2">
              {items.map((item) => (
                <button
                  key={item.id}
                  onClick={() => onPurchase(item.id)}
                  disabled={coins < item.price}
                  className="w-full flex items-center justify-between p-2 rounded-lg hover:bg-gray-50
                    disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <span className="flex items-center gap-2">
                    <span className="text-2xl">{item.icon}</span>
                    <span className="font-medium">{item.name}</span>
                  </span>
                  <span className="text-sm font-semibold text-gray-600">
                    🪙 {item.price}
                  </span>
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}