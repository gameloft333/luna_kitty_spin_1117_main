import React, { useState, useEffect } from 'react';
import CatDisplay from './components/CatDisplay';
import SlotMachine from './components/SlotMachine';
import Shop from './components/Shop';
import type { GameState, SlotResult } from './types/game';
import { SYMBOLS } from './types/game';

const INITIAL_STATE: GameState = {
  coins: 100,
  catStats: {
    health: 100,
    mood: 100,
    adoptionDays: 0,
  },
  isSpinning: false,
  autoSpin: false,
};

function App() {
  const [gameState, setGameState] = useState<GameState>(INITIAL_STATE);

  useEffect(() => {
    const timer = setInterval(() => {
      setGameState(prev => ({
        ...prev,
        catStats: {
          ...prev.catStats,
          health: Math.max(0, prev.catStats.health - 0.1),
          mood: Math.max(0, prev.catStats.mood - 0.15),
          adoptionDays: prev.catStats.adoptionDays + (1/24/60), // Increment by 1 minute
        }
      }));
    }, 1000);

    return () => clearInterval(timer);
  }, []);

  const handleSpin = (results: SlotResult[]) => {
    setGameState(prev => {
      const newState = { ...prev, isSpinning: true };
      
      setTimeout(() => {
        setGameState(current => {
          const rewards = results.reduce((acc, result) => {
            const symbol = SYMBOLS[result.symbol];
            switch (symbol.type) {
              case 'coin':
                acc.coins += result.value;
                break;
              case 'health':
                acc.health += result.value;
                break;
              case 'mood':
                acc.mood += result.value;
                break;
              case 'special':
                acc.health += result.value;
                acc.mood += result.value;
                acc.coins += Math.floor(result.value / 2);
                break;
            }
            return acc;
          }, {
            coins: 0,
            health: 0,
            mood: 0,
          });

          return {
            ...current,
            isSpinning: false,
            coins: current.coins + rewards.coins,
            catStats: {
              ...current.catStats,
              health: Math.min(100, current.catStats.health + rewards.health),
              mood: Math.min(100, current.catStats.mood + rewards.mood),
            }
          };
        });
      }, 1000);

      return newState;
    });
  };

  const handlePurchase = (item: string) => {
    setGameState(prev => {
      const costs = { growth: 50, health: 30, mood: 20 };
      const cost = costs[item as keyof typeof costs];
      
      if (prev.coins < cost) return prev;

      const benefits = {
        growth: { health: 20, mood: 20 },
        health: { health: 40 },
        mood: { mood: 40 },
      };

      const benefit = benefits[item as keyof typeof benefits];

      return {
        ...prev,
        coins: prev.coins - cost,
        catStats: {
          ...prev.catStats,
          health: Math.min(100, prev.catStats.health + (benefit.health || 0)),
          mood: Math.min(100, prev.catStats.mood + (benefit.mood || 0)),
        }
      };
    });
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-pink-100 via-purple-100 to-indigo-100">
      <div className="container mx-auto px-4 py-8 flex flex-col items-center gap-8 max-w-sm">
        <h1 className="text-4xl font-bold text-center text-purple-800">
          Luna Kitty Spin 🐱
        </h1>

        <CatDisplay stats={gameState.catStats} />
        
        <div className="flex justify-center items-center">
          <div className="text-2xl font-bold text-yellow-600">
            🪙 {gameState.coins}
          </div>
        </div>

        <SlotMachine
          isSpinning={gameState.isSpinning}
          autoSpin={gameState.autoSpin}
          onSpin={handleSpin}
          onAutoSpinToggle={() => 
            setGameState(prev => ({ ...prev, autoSpin: !prev.autoSpin }))
          }
        />

        <Shop coins={gameState.coins} onPurchase={handlePurchase} />
      </div>
    </div>
  );
}

export default App;